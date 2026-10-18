local MacWorkflows = require("../../../tools/lib/mac-workflows")

local serde = require("@lune/serde")

local function check(yaml: string): { string }
	return MacWorkflows.check("w.yml", serde.decode("yaml", MacWorkflows.explicit(yaml)))
end

local READ = "    permissions:\n      contents: read\n      actions: read\n"

-- One job; `environment` defaults to studio, and false leaves it out;
-- `permissions` defaults to READ.
local function workflow(on: string, runsOn: string, environment: (string | false)?, permissions: string?): string
	local env = if environment == false then "" else `    environment: {environment or "studio"}\n`
	return `on:\n{on}\njobs:\n  play:\n    runs-on: {runsOn}\n{env}{permissions or READ}    steps: []\n`
end

local JOB = "jobs:\n  play:\n    runs-on: self-hosted\n    environment: studio\n" .. READ

return function(t: any)
	t.describe("mac-workflows", function()
		t.it("ignores a workflow whose jobs all run on GitHub's runners", function()
			t.expect(check(workflow("  pull_request:", "ubuntu-latest"))).toEqual({})
			t.expect(check(workflow("  pull_request:", "[macos-15]"))).toEqual({})
		end)

		t.it("accepts a Mac job started by hand, on a schedule or by a push to main", function()
			t.expect(check(workflow("  workflow_dispatch:", "[self-hosted, studio]"))).toEqual({})
			t.expect(check(workflow("  schedule:\n    - cron: '0 3 * * *'", "[self-hosted, studio]"))).toEqual({})
			t.expect(check(workflow("  push:\n    branches: [main]", "[self-hosted, studio]"))).toEqual({})
		end)

		t.it("refuses a Mac job started from a pull request, however the trigger is written", function()
			local problem =
				"w.yml: runs on the Mac and starts on 'pull_request'; only workflow_dispatch, schedule, push may start a Mac job"
			t.expect(check(workflow("  pull_request:\n    types: [labeled]", "[self-hosted, studio]")))
				.toEqual({ problem })
			t.expect(check("on: pull_request\n" .. JOB)).toEqual({ problem })
			t.expect(check("on: [workflow_dispatch, pull_request]\n" .. JOB)).toEqual({ problem })
		end)

		t.it("refuses pull_request_target, workflow_run and workflow_call on the Mac", function()
			for _, name in { "pull_request_target", "workflow_run", "workflow_call" } do
				t.expect(#check(workflow(`  {name}:`, "[self-hosted, studio]"))).toBe(1)
			end
		end)

		t.it("refuses a push to anything but main", function()
			local problem = "w.yml: runs on the Mac and starts on a push; only 'branches: [main]' may"
			for _, branches in { "", "\n    branches: [my-branch]", "\n    branches: [main, my-branch]" } do
				t.expect(check(workflow(`  push:{branches}`, "[self-hosted, studio]"))).toEqual({ problem })
			end
		end)

		t.it("requires every Mac job to use the studio environment", function()
			local problem = "w.yml: job 'play' runs on the Mac without 'environment: studio'"
			t.expect(check(workflow("  workflow_dispatch:", "[self-hosted, studio]", false))).toEqual({ problem })
			t.expect(check(workflow("  workflow_dispatch:", "[self-hosted, studio]", "dev"))).toEqual({ problem })
			t.expect(check(workflow("  workflow_dispatch:", "[self-hosted, studio]", "{ name: studio }"))).toEqual({})
			t.expect(check(workflow("  workflow_dispatch:", "ubuntu-latest", false))).toEqual({})
		end)

		t.it("counts a label of our own, a runner group and an expression as the Mac", function()
			for _, runsOn in
				{ "studio", "[studio]", "{ group: mac }", "${{ inputs.runner }}", "[self-hosted, macos-15]" }
			do
				t.expect(#check(workflow("  pull_request:", runsOn))).toBe(1)
			end
		end)

		t.it("finds the Mac job among others", function()
			local yaml = "on:\n  pull_request:\njobs:\n  a:\n    runs-on: ubuntu-latest\n  b:\n    runs-on: [self-hosted]\n    environment: studio\n"
				.. READ
			t.expect(#check(yaml)).toBe(1)
		end)

		t.it("requires every Mac job to declare its own permissions, none beyond read", function()
			local dispatch, mac = "  workflow_dispatch:", "[self-hosted, studio]"
			t.expect(
				check(
					workflow(dispatch, mac, nil, "    permissions:\n      contents: read\n      pull-requests: none\n")
				)
			)
				.toEqual({})
			t.expect(check(workflow(dispatch, mac, nil, ""))).toEqual({
				"w.yml: job 'play' runs on the Mac without its own read-only 'permissions'",
			})
			t.expect(check(workflow(dispatch, mac, nil, "    permissions: write-all\n"))).toEqual({
				"w.yml: job 'play' runs on the Mac without its own read-only 'permissions'",
			})
			t.expect(check(workflow(dispatch, mac, nil, "    permissions:\n      contents: write\n"))).toEqual({
				"w.yml: job 'play' runs on the Mac with 'contents: write'; a Mac job may only read",
			})
		end)

		t.it("refuses a secret in a Mac job, wherever it is named", function()
			local yaml = "on:\n  workflow_dispatch:\n"
				.. JOB
				.. "    steps:\n      - run: x\n        env:\n          KEY: ${{ secrets.KEY }}\n"
			t.expect(check(yaml)).toEqual({ "w.yml: job 'play' runs on the Mac and names a secret" })
			for _, named in { "${{ toJSON(secrets) }}", "${{ secrets['KEY'] }}" } do
				t.expect(check(`on:\n  workflow_dispatch:\n{JOB}    steps:\n      - run: echo "{named}"\n`)).toEqual({
					"w.yml: job 'play' runs on the Mac and names a secret",
				})
			end
			t.expect(check(`on:\n  workflow_dispatch:\n{JOB}    steps:\n      - run: echo mysecrets_list\n`))
				.toEqual({})
		end)

		t.it("lets a GitHub-hosted job beside a Mac job write and use secrets", function()
			local yaml = "on:\n  workflow_dispatch:\n"
				.. JOB
				.. "  publish:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: write\n      pull-requests: write\n"
				.. "    steps:\n      - run: x\n        env:\n          T: ${{ secrets.T }}\n"
			t.expect(check(yaml)).toEqual({})
		end)

		t.it("leaves a job that calls a reusable workflow to that workflow's own check", function()
			t.expect(check("on:\n  pull_request:\njobs:\n  a:\n    uses: ./.github/workflows/other.yml\n")).toEqual({})
		end)

		t.it("writes an empty map after a key with no value, and only there", function()
			local yaml =
				"on:\n  workflow_dispatch:\n  push: # by hand\n\n  schedule:\n    - cron: x\njobs:\n  a:\n    steps:\n    - run: x\n"
			t.expect(MacWorkflows.explicit(yaml)).toBe(
				"on:\n  workflow_dispatch: {}\n  push: {}\n\n  schedule:\n    - cron: x\njobs:\n  a:\n    steps:\n    - run: x\n"
			)
		end)

		t.it("refuses what is not a workflow", function()
			t.expect(check("name: nothing")).toEqual({ "w.yml: is not a workflow (no jobs)" })
		end)
	end)
end
