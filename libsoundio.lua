
--libsoundio binding.
--Written by Cosmin Apreutesei. Public Domain.

local ffi = require'ffi'
require'libsoundio_h'

local C = ffi.load'soundio'
local M = {C = C}

local function checkptr(p)
	assert(p ~= nil)
	return p
end

local function ringbuffer_free(self)
	ffi.gc(self, nil)
	C.soundio_ring_buffer_destroy(self)
end

function M.ringbuffer(sio, capacity)
	return ffi.gc(checkptr(C.soundio_ring_buffer_create(sio, capacity)), ringbuffer_free)
end

ffi.metatype('struct SoundIoRingBuffer', {__index = {
	free = ringbuffer_free,
	capacity = C.soundio_ring_buffer_capacity,
	write_ptr = C.soundio_ring_buffer_write_ptr,
	advance_write_ptr = C.soundio_ring_buffer_advance_write_ptr,
	read_ptr = C.soundio_ring_buffer_read_ptr,
	advance_read_ptr = C.soundio_ring_buffer_advance_read_ptr,
	fill_count = C.soundio_ring_buffer_fill_count,
	free_count = C.soundio_ring_buffer_free_count,
	clear = C.soundio_ring_buffer_clear,
}})

if not ... then

	local sio = M
	local winapi = require'winapi'
	local lua = require'luastate'

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

	local PI = math.pi

	local ring = true

	local state = lua.open()
	state:openlibs()
	state:push(function(ringbuffer_ptr, ring)

		local ffi = require'ffi'
		local sio = require'libsoundio'
		local C = sio.C

		local exit = os.exit
		local stderr = io.stderr
		local stdin = io.stdin

		local function soundio_strerror(err)
			return ffi.string(C.soundio_strerror(err))
		end

		local function fprintf(f, ...)
			f:write(string.format(...))
		end

		local function protect(func)
			local function pass(ok, ...)
				if not ok then
					fprintf(stderr, "error: %s", (...))
					exit(1)
				end
				return ...
			end
			return function(...)
				return pass(xpcall(func, debug.traceback, ...))
			end
		end

		local PI = math.pi

		local ringbuffer = ffi.cast('struct SoundIoRingBuffer*', ringbuffer_ptr)

		local seconds_offset = 0

		local function write_callback(outstream, frame_count_min, frame_count_max)
			print(outstream, frame_count_min, frame_count_max)

			local float_sample_rate = outstream.sample_rate
			local seconds_per_frame = 1 / float_sample_rate
			local err

			local fill_bytes, read_buf, frames_left

			if ring then

				fill_bytes = ringbuffer:fill_count()
				read_buf = ringbuffer:read_ptr()
				fill_bytes = math.min(fill_bytes, frame_count_max * 4)
				frames_left = math.floor(fill_bytes / 4)

			else

				frames_left = frame_count_max

			end

			if frames_left <= 0 then return end

			local frame_count = ffi.new('int[1]', frames_left)
			local areas = ffi.new'struct SoundIoChannelArea*[1]'

			while true do
				local err = C.soundio_outstream_begin_write(outstream, areas, frame_count)
				if err ~= 0 then
					fprintf(stderr, "unrecoverable stream error: %s\n", soundio_strerror(err))
					exit(1)
				end
				local areas = areas[0]
				local frame_count = frame_count[0]

				if frame_count == 0 then
					break
				end

				if ring then

					print(fill_bytes)
					ffi.copy(areas[0].ptr, read_buf, fill_bytes)
					ringbuffer:advance_read_ptr(fill_bytes)
					areas[0].ptr = areas[0].ptr + fill_bytes
					areas[1].ptr = areas[1].ptr + fill_bytes

				else

					local pitch = 440
					local radians_per_second = pitch * 2 * PI
					local n = 0
					for channel = 0, outstream.layout.channel_count-1 do
						local buf = ffi.cast('int16_t*', areas[channel].ptr)
						for frame = 0, frame_count-1 do
							buf[frame * 2] = 2000 * math.sin((seconds_offset + frame * seconds_per_frame) * radians_per_second)
						end
						areas[channel].ptr = areas[channel].ptr + frame_count * 2
					end
					seconds_offset = seconds_offset + seconds_per_frame * frame_count

				end

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
		local write_cb = ffi.cast('SoundIoWriteCallback', protect(write_callback))

		local count = 0
		local function underflow_callback(outstream)
			print(string.format("underflow %d\n", count))
			count = count + 1
		end
		local underflow_cb = ffi.cast('SoundIoUnderflowCallback', protect(underflow_callback))

		return
			tonumber(ffi.cast('intptr_t', write_cb)),
			tonumber(ffi.cast('intptr_t', underflow_cb))

	end)

	local backend = C.SoundIoBackendWasapi
	local raw = false
	local stream_name = nil
	local latency = 0
	local sample_rate = 0

	local soundio = C.soundio_create()
	assert(soundio ~= nil)

	local ringbuffer = sio.ringbuffer(soundio, 44100)
	local write_callback, underflow_callback = state:call(
		tonumber(ffi.cast('intptr_t', ringbuffer)),
		ring)
	write_callback = ffi.cast('SoundIoWriteCallback', write_callback)
	underflow_callback = ffi.cast('SoundIoUnderflowCallback', underflow_callback)

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

	local err = C.soundio_outstream_start(outstream)
	if err ~= 0 then
		fprintf(stderr, "unable to start device: %s\n", soundio_strerror(err))
		exit(1)
	end

	local seconds_offset = 0

	while true do
		C.soundio_flush_events(soundio)

		if ring then

			local time = require'time'

			local write_ptr = ringbuffer:write_ptr()
			local free_bytes = ringbuffer:free_count()
			local frame_count = math.floor(free_bytes / outstream.bytes_per_frame)

			if frame_count >= 0 then

				local float_sample_rate = outstream.sample_rate
				local seconds_per_frame = 1 / float_sample_rate

				local pitch = 440
				local radians_per_second = pitch * 2 * PI
				local n = 0
				for channel = 0, outstream.layout.channel_count-1 do
					local buf = ffi.cast('int16_t*', write_ptr) + channel
					for frame = 0, frame_count-1 do
						buf[frame * 2] = 2000 * math.sin((seconds_offset + frame * seconds_per_frame) * radians_per_second)
					end
				end
				seconds_offset = seconds_offset + seconds_per_frame * frame_count

				ringbuffer:advance_write_ptr(frame_count * 4)

			end

			time.sleep(0.1)

		else

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
	end

	C.soundio_outstream_destroy(outstream)
	C.soundio_device_unref(device)
	C.soundio_destroy(soundio)
end

return M
