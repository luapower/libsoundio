local soundio = require'libsoundio'
local ffi = require'ffi'
local lua = require'luastate'
local time = require'time'

local sio = soundio.new()
sio:connect()

--reflection -----------------------------------------------------------------

local idev = sio:devices'*i'
local odev = sio:devices'*o'
local idev_raw = sio:devices('*i', true)
local odev_raw = sio:devices('*o', true)
print(idev.id == (idev_raw and idev_raw.id), idev == idev_raw)

print'Devices'
for dev in sio:devices() do
	print('  '..
		(dev == idev and '*i' or
		dev == odev and '*o' or ' '..dev.aim)..
		(dev.is_raw and '/raw' or '    '),
		dev.id, dev.name)
end

odev:print()

--buffered streaming ---------------------------------------------------------

local dev = odev
assert(not dev.probe_error, 'device probing error')

local str = dev:stream()
str.sample_rate = 44100
str:open()
assert(not str.layout_error, 'unable to set channel layout')

local buf = str:buffer() --make a 1s buffer
str:clear_buffer()

local function play_vorbis_file()

	local vf = require'libvorbis_file'

	local vf = vf.open{path = 'media/ogg/06 A Colloquial Dream.ogg'}

	vf:print()

	assert(str.layout.channel_count == 2)
	assert(vf:info().channels == 2)
	assert(vf:info().rate == str.sample_rate)

	local sbuf = ffi.new'int16_t[4096]'

	str:start()

	while true do
		local p, n = buf:write_buf()
		print(p, n)
		if n > 0 then

			--fill up the buffer
			local bn = vf:read(sbuf, n * 4)
			local fn = math.floor(bn/4)
			if fn == 0 then break end

			for channel = 0, 1 do
				for i = 0, n-1 do
					p[i][channel] = sbuf[i * 2 + channel] / (2^15-1)
				end
			end
			buf:advance_write_ptr(n)
		end
		time.sleep(0.01)
	end

	while buf:fill_count() > 0 or str:latency() > 0 do
		print(str:latency())
		time.sleep(0.1)
	end

end

local function play_tone()

	local pitch = 440
	local volume = 0.1
	local sin_factor = 2 * math.pi / str.sample_rate * pitch
	local frame0 = 0
	local function sample(frame, channel)
		local octave = channel + 1
		return volume * math.sin((frame0 + frame) * sin_factor * octave)
	end

	local duration, interval = 1, 0.05
	print(string.format('Playing L=%dHz R=%dHz for %ds...', pitch, pitch * 2, duration))

	str:start()

	for i = 1, duration / interval do
		local p, n = buf:write_buf()
		if n > 0 then
			print(string.format('latency: %-.2fs, empty: %3d%%',
				str:latency(), n / buf:capacity() * 100))
			for channel = 0, str.layout.channel_count-1 do
				for i = 0, n-1 do
					p[i][channel] = sample(i, channel)
				end
			end
			buf:advance_write_ptr(n)
			frame0 = frame0 + n
		end
		time.sleep(interval)
	end

end

--play_vorbis_file()
play_tone()

buf:free()
str:free()
sio:free()
print'Done'
