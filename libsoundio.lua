
--libsoundio binding.
--Written by Cosmin Apreutesei. Public Domain.

local ffi = require'ffi'
require'libsoundio_h'

local C = ffi.load'soundio'
local M = {}

if not ... then

	local winapi = require'winapi'
	require'winapi.winbase'
	local tid = winapi.GetCurrentThreadId

	local exit = os.exit
	local stderr = io.stderr
	local stdin = io.stdin

	local function soundio_strerror(err)
		return ffi.string(C.soundio_strerror(err))
	end

	local function fprintf(f, ...)
		f:write(string.format(...))
	end

	local function getc(f)
		return f:read(1)
	end

	local function write_sample(ptr, sample)
		local buf = ffi.cast('int16_t*', ptr)
		local range = 2^32
		local val = sample * range / 2
		buf[0] = val
	end

	local PI = math.pi
	local seconds_offset = 0

	local function write_callback(outstream, frame_count_min, frame_count_max)
		print(tid(), outstream, frame_count_min, frame_count_max)

		local float_sample_rate = outstream.sample_rate
		local seconds_per_frame = 1 / float_sample_rate
		local areas = ffi.new'SoundIoChannelArea*[1]'
		local err

		local frames_left = frame_count_max

		while true do
			local frame_count = ffi.new('int[1]', frames_left)
			local err = C.soundio_outstream_begin_write(outstream, areas, frame_count)
			if err ~= 0 then
				fprintf(stderr, "unrecoverable stream error: %s\n", soundio_strerror(err))
				exit(1)
			end

			if frame_count == 0 then
				break
			end

			local layout = ffi.new('SoundIoChannelLayout*[1]', outstream.layout)

			local pitch = 440
			local radians_per_second = pitch * 2 * PI
			for frame = 0, frame_count-1 do
				local sample = math.sin((seconds_offset + frame * seconds_per_frame) * radians_per_second)
				for channel = 0, layout.channel_count-1 do
					write_sample(areas[channel].ptr, sample)
					areas[channel].ptr = areas[channel].ptr + areas[channel].step
				end
			end
			seconds_offset = seconds_offset + seconds_per_frame * frame_count

			local err = C.soundio_outstream_end_write(outstream)
			if err == C.SoundIoErrorUnderflow then
				return
			elseif err ~= 0 then
				fprintf(stderr, "unrecoverable stream error: %s\n", C.soundio_strerror(err))
				exit(1)
			end

			frames_left = frames_left - frame_count
			if frames_left <= 0 then
				break
			end
		end
	end

	local count = 0
	local function underflow_callback(outstream)
		print(string.format("underflow %d\n", count))
		count = count + 1
	end

	local backend = C.SoundIoBackendWasapi
	local raw = false
	local stream_name = nil
	local latency = 0
	local sample_rate = 0

	local soundio = C.soundio_create()
	assert(soundio ~= nil)

	local err = C.soundio_connect_backend(soundio, backend)
	if err ~= 0 then
		fprintf(stderr, "Unable to connect to backend: %s\n", soundio_strerror(err))
		exit(1)
	end

	C.soundio_flush_events(soundio)

	local selected_device_index = C.soundio_default_output_device_index(soundio)
	assert(selected_device_index >= 0)

	local device = C.soundio_get_output_device(soundio, selected_device_index)
	assert(device ~= nil)

	if device.probe_error ~= 0 then
		fprintf(stderr, "Cannot probe device: %s\n", soundio_strerror(device.probe_error))
		exit(1)
	end

	assert(C.soundio_device_supports_format(device, C.SoundIoFormatS16NE) ~= 0)

	local outstream = C.soundio_outstream_create(device)
	outstream.write_callback = write_callback
	outstream.underflow_callback = underflow_callback
	outstream.name = stream_name
	outstream.software_latency = latency
	outstream.sample_rate = sample_rate
	outstream.format = C.SoundIoFormatS16NE

	local err = C.soundio_outstream_open(outstream)
	if err ~= 0 then
		fprintf(stderr, "unable to open device: %s", soundio_strerror(err))
		exit(1)
	end

	if outstream.layout_error ~= 0 then
		fprintf(stderr, "unable to set channel layout: %s\n", soundio_strerror(outstream.layout_error))
		exit(1)
	end

	print('main thread id: ', tid())

	local err = C.soundio_outstream_start(outstream)
	if err ~= 0 then
		fprintf(stderr, "unable to start device: %s\n", soundio_strerror(err))
		exit(1)
	end

	while true do
		C.soundio_flush_events(soundio)
		local c = getc(stdin)
		if c == 'p' then
			fprintf(stderr, "pausing result: %s\n",
					  soundio_strerror(C.soundio_outstream_pause(outstream, true)))
		elseif c == 'u' then
			fprintf(stderr, "unpausing result: %s\n",
					  soundio_strerror(C.soundio_outstream_pause(outstream, false)))
		elseif c == 'c' then
			fprintf(stderr, "clear buffer result: %s\n",
					  soundio_strerror(C.soundio_outstream_clear_buffer(outstream)))
		elseif c == 'q' then
			break;
		elseif c == '\r' or c == '\n' then
			-- ignore
		else
			fprintf(stderr, "Unrecognized command: %c\n", c)
		end
	end

	C.soundio_outstream_destroy(outstream)
	C.soundio_device_unref(device)
	C.soundio_destroy(soundio)
end

return M
