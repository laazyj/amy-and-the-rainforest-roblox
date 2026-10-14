--!strict
-- Reads the brightness of an uncompressed BMP, the one image format that is
-- simple enough to read here; studio.luau has `sips` convert the screenshot.
-- Pure, so the spec covers it.

local Bmp = {}

-- The mean luminance of the image, 0 (black) to 1 (white). Understands 24-bit
-- BGR and 32-bit BGRA pixels, which is what `sips -s format bmp` writes.
function Bmp.luminance(bytes: string): number
	if string.sub(bytes, 1, 2) ~= "BM" or #bytes < 54 then
		error("not a BMP image", 0)
	end
	local data = buffer.fromstring(bytes)
	local pixels = buffer.readu32(data, 10)
	local width = buffer.readi32(data, 18)
	local height = math.abs(buffer.readi32(data, 22))
	local bytesPerPixel = buffer.readu16(data, 28) / 8
	if bytesPerPixel ~= 3 and bytesPerPixel ~= 4 then
		error(`unsupported BMP: {bytesPerPixel * 8} bits per pixel`, 0)
	end
	-- Rows are padded to four bytes.
	local stride = math.ceil(width * bytesPerPixel / 4) * 4
	if width <= 0 or height == 0 or pixels + stride * height > #bytes then
		error("truncated BMP image", 0)
	end
	local sum = 0
	for row = 0, height - 1 do
		local offset = pixels + row * stride
		for column = 0, width - 1 do
			local pixel = offset + column * bytesPerPixel
			-- Rec. 709 weights; the bytes are blue, green, red.
			sum += 0.0722 * buffer.readu8(data, pixel) + 0.7152 * buffer.readu8(data, pixel + 1) + 0.2126 * buffer.readu8(
				data,
				pixel + 2
			)
		end
	end
	return sum / (width * height * 255)
end

return Bmp
