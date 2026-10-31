#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>

#include "RtMidi.h"

namespace godot {

// Thin wrapper around RtMidiOut, exposed to GDScript as `MidiOutDevice`.
class MidiOutDevice : public RefCounted {
	GDCLASS(MidiOutDevice, RefCounted)

private:
	std::unique_ptr<::RtMidiOut> out;

protected:
	static void _bind_methods();

public:
	MidiOutDevice();
	~MidiOutDevice();

	int get_port_count();
	String get_port_name(int index);
	bool open_port(int index);
	bool open_virtual_port(const String &name);
	void close_port();
	bool is_port_open() const;
	bool send_message(const PackedByteArray &bytes);
	String get_api_name() const;
};

} // namespace godot
