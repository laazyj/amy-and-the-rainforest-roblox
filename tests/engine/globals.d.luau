-- Type declarations for engine test scripts (tests/engine/ only), used by
-- tools/check.sh. EngineTests.wrap in tools/lib/engine-tests.luau defines
-- these before each script: RUN_ID and PASS_MARKER as globals, the rest as
-- locals bound from tests/engine/_prelude.luau (`game` is already in Roblox's
-- definitions), then the runner's include and fixture
-- (EngineTests.EMBED_FUNCTIONS). A unit test checks these against both lists.

declare RUN_ID: string
declare PASS_MARKER: string

type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeTruthy: () -> (),
	toBeNil: () -> (),
	toThrow: () -> (),
}

declare function describe(name: string, fn: () -> ()): ()
declare function it(name: string, fn: () -> ()): ()
declare function expect(value: any): Expectation
declare function storeName(base: string): string
declare function finish(): ()
declare function include(path: string): any
declare function fixture(path: string): string
