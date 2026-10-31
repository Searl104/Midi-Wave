#include "midi_out_device.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <vector>

using namespace godot;

static void rtmidi_error_callback(RtMidiError::Type type, const std::string &text, void *) {
	String msg = String("MIDI: ") + String::utf8(text.c_str());
	if (type == RtMidiError::WARNING || type == RtMidiError::DEBUG_WARNING) {
		UtilityFunctions::push_warning(msg);
	} else {
		UtilityFunctions::push_error(msg);
	}
}

void MidiOutDevice::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_port_count"), &MidiOutDevice::get_port_count);
	ClassDB::bind_method(D_METHOD("get_port_name", "index"), &MidiOutDevice::get_port_name);
	ClassDB::bind_method(D_METHOD("open_port", "index"), &MidiOutDevice::open_port);
	ClassDB::bind_method(D_METHOD("open_virtual_port", "name"), &MidiOutDevice::open_virtual_port);
	ClassDB::bind_method(D_METHOD("close_port"), &MidiOutDevice::close_port);
	ClassDB::bind_method(D_METHOD("is_port_open"), &MidiOutDevice::is_port_open);
	ClassDB::bind_method(D_METHOD("send_message", "bytes"), &MidiOutDevice::send_message);
	ClassDB::bind_method(D_METHOD("get_api_name"), &MidiOutDevice::get_api_name);
}

MidiOutDevice::MidiOutDevice() {
	try {
		out = std::make_unique<::RtMidiOut>(RtMidi::UNSPECIFIED, "Godot MIDI Driver");
		// With a callback set, RtMidi reports errors here instead of throwing.
		out->setErrorCallback(&rtmidi_error_callback, nullptr);
	} catch (RtMidiError &e) {
		UtilityFunctions::push_error(String("MIDI: could not initialise output: ") + String::utf8(e.getMessage().c_str()));
		out.reset();
	}
}

MidiOutDevice::~MidiOutDevice() {
	close_port();
}

int MidiOutDevice::get_port_count() {
	return out ? (int)out->getPortCount() : 0;
}

String MidiOutDevice::get_port_name(int index) {
	if (!out || index < 0) {
		return String();
	}
	return String::utf8(out->getPortName((unsigned int)index).c_str());
}

bool MidiOutDevice::open_port(int index) {
	if (!out || index < 0 || index >= get_port_count()) {
		return false;
	}
	close_port();
	out->openPort((unsigned int)index, "Godot MIDI Driver Out");
	return out->isPortOpen();
}

bool MidiOutDevice::open_virtual_port(const String &name) {
	if (!out) {
		return false;
	}
	close_port();
	out->openVirtualPort(name.utf8().get_data());
	// Virtual ports don't report isPortOpen() on every backend; assume success
	// unless the error callback fired (it will have logged).
	return true;
}

void MidiOutDevice::close_port() {
	if (out) {
		out->closePort();
	}
}

bool MidiOutDevice::is_port_open() const {
	return out && out->isPortOpen();
}

bool MidiOutDevice::send_message(const PackedByteArray &bytes) {
	if (!out || bytes.is_empty()) {
		return false;
	}
	out->sendMessage(bytes.ptr(), (size_t)bytes.size());
	return true;
}

String MidiOutDevice::get_api_name() const {
	if (!out) {
		return "unavailable";
	}
	return String::utf8(RtMidi::getApiDisplayName(out->getCurrentApi()).c_str());
}
