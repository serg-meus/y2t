module main

import os
import json
import time
import encoding.utf8 { is_letter }
import net.http.file { serve }
import dariotarantini.vgram { Bot, Update }

struct Props {
	yt_dlp_path     string @[required]
	yt_dlp_json     string @[required]
	welcome_message string @[required]
	start_load_msg  string @[required]
	success_message string @[required]
	yt_dlp_options  string @[required]
	error           string @[required]
	turned_on       string @[required]
	turned_off      string @[required]
	only_audio      string @[required]
	not_realized    string @[required]
	already_downld  string @[required]
	update_limit    int    @[required]
	downld_shutdown int    @[required]
mut:
	server_ip string
}

struct Secrets {
	bot_key   string @[required]
	server_ip string @[required]
}

struct VideoProps {
	title string
	id    string
	ext   string
}

struct UserProps {
pub mut:
	audio bool
	best  bool
	zip   bool
}

fn main() {
	mut lines := os.read_lines('settings.json') or { panic('File settings.json not found') }
	mut props := json.decode(Props, lines.join(' ')) or { panic("Can't decode settings.json") }
	mut user_props := map[string]UserProps{}
	lines = os.read_lines('secrets.json') or { panic('File secrets.json not found') }
	secrets := json.decode(Secrets, lines.join(' ')) or { panic("Can't decode secrets.json") }
	bot := vgram.new_bot(secrets.bot_key)
	props.server_ip = secrets.server_ip
	mut updates := []Update{}
	mut last_offset := 0
	println('The bot started successfully')
	mut just_started := true
	for {
		updates = bot.get_updates(offset: last_offset, limit: props.update_limit)
		for update in updates {
			if last_offset < update.update_id {
				last_offset = update.update_id
				if !just_started {
					react(bot, update, props, mut &user_props)
				}
				just_started = false
			}
		}
	}
}

// def main

fn react(bot Bot, update Update, props Props, mut user_props map[string]UserProps) {
	msg := update.message.text.trim_space()
	id := update.message.from.id.str()
	if msg == '/start' {
		bot.send_message(chat_id: id, text: props.welcome_message)
		user_props[id] = UserProps{}
	} else if msg.starts_with('http') || msg.starts_with('www') {
		println('${time.now()} ${id} ${msg}')
		bot.send_message(chat_id: id, text: props.start_load_msg)
		err := download_video(msg, props, user_props[id])
		ans := if err.int() == 0 {
			props.success_message + ' http://' + props.server_ip + '/' + err
		} else {
			props.error + ' ${err}'
		}
		bot.send_message(chat_id: id, text: ans)
	} else if msg == '/ping' {
		bot.send_message(chat_id: id, text: 'pong')
	} else if msg == '/audio' {
		user_props[id].audio = !user_props[id].audio
		mode_tx := if user_props[id].audio { props.turned_on } else { props.turned_off }
		bot.send_message(chat_id: id, text: mode_tx + ' ' + props.only_audio)
	} else if msg.starts_with('/') {
		bot.send_message(chat_id: id, text: props.not_realized)
	}
}

fn download_video(msg string, props Props, user_props UserProps) string {
	cmd_get_json := props.yt_dlp_path + props.yt_dlp_json + msg + ' > tmp.json'
	os.execute_opt(cmd_get_json) or { return '404' }
	lines := os.read_lines('tmp.json') or { return '2' }
	video := json.decode(VideoProps, lines.join(' ')) or { return '3' }
	ext := if user_props.audio { 'mp3' } else { 'mp4' }
	title := remove_bad_symbols(video.title)
	splt := title.split('_')
	max_len := if splt.len > 5 { 5 } else { splt.len }
	mut dl_props := props.yt_dlp_options + ' '
	if user_props.audio {
		dl_props += '-x --audio-format mp3 '
	}
	ending := '_' + video.id + '.' + ext
	new_filename := 'download/' + percent_encoding(splt[..max_len].join('_') + ending)
	if !os.exists(new_filename) {
		cmd_download := props.yt_dlp_path + '/yt-dlp ' + dl_props + msg
		println(cmd_download)
		os.execute_opt(cmd_download) or { return '4' }
		os.execute_opt('mv *' + video.id + '.' + ext + ' ' + new_filename) or { return '5' }
	} else {
		println(props.already_downld)
	}
	spawn serve(on: props.server_ip, shutdown_after: props.downld_shutdown * time.minute)
	return new_filename
}

fn remove_bad_symbols(str string) string {
	mut ans := str.runes()
	forbidden_symbols := '!@#$%^&*/|\\ \t\'"'.runes()
	rep := '_'.runes()[0]
	for i, wchr in ans {
		if wchr in forbidden_symbols || !is_letter(wchr) {
			ans[i] = rep
		}
	}
	mut tmp := ''.runes()
	for i, wchr in ans {
		if i == 0 || (wchr != rep || ans[i - 1] != rep) {
			tmp << wchr
		}
	}
	return tmp.string()
}

fn percent_encoding(url string) string {
	mut state := true
	mut ans := ''.bytes()
	for b in url.bytes() {
		if state && b < 128 {
			ans << b.ascii_str()[0]
		} else {
			state = !state
			ans << '%'[0]
			ans << b.hex().to_upper()[0]
			ans << b.hex().to_upper()[1]
		}
	}
	return ans.bytestr()
}

fn file_exists_ends_with(ending string, path string) bool {
	entries := os.ls('.') or { [] }
	for e in entries {
		if !os.is_dir(e) && e.ends_with(ending) {
			return true
		}
	}
	return false
}
