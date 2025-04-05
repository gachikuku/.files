#!/bin/sh

text="$1"

# match(str, regex, [flags])
match() {
	printf '%s' "$1" | grep "-qE$3" "$2"
}

# isallowedproto(url)
isallowedproto() {
	match "$1" '^(http|https|gopher|gophers|rtmp|lbry|ytdl)://'
}

# isgraphical mode? X11 or not.
isgraphical() {
	test -n "$DISPLAY"
}

# image(url)
image() {
	# scale to fit (-s f).
	# private mode (no cache), (-p).
	test -n "$1" && sxiv -p -s f "$1"
}

# pdf(url)
pdf() {
	test -n "$1" && mupdf "$1"
}

# www(url)
www() {
	test -n "$1" || return
#	isgraphical && "${BROWSER}" "$1" || lynx "$1"
	open -a Safari "$1"
}

#audio(url)
audio() {
	test -n "$1" && mpv "$1"
}

convert_to_embed() {
    local url=$1
    local video_id=${url#*v=}
    video_id=${video_id%%&*}
    local embed_url="https://www.youtube.com/embed/$video_id"
    echo "$embed_url"
}

# movie(url)
movie() {
	#test -n "$1" && mpv --autofit=100%x100% "$1"
	test -n "$1" && embed_url=$(convert_to_embed "$1")
	open -a Safari "$embed_url"
}

# handle pastebin-like url.
# pastebin(url)
pastebin() {
	st -e less "$1"
}

# fetch(url)
fetch() {
	curl -H 'User-Agent:' -m 30 "$1"
}

# download file, invoke a function on the text, delete temporary file.
# tempview(fn, text)
tempview() {
	tmp=$(mktemp)
	fetch "$2" > "$tmp"
	test -f "$tmp" && "$1" "$tmp"
	rm -f "$tmp"
}

# check allowed protocols.
if ! isallowedproto "$text"; then
	echo "disallowed proto for $text" >&2
	exit 1
fi

# specified action.
# this is always a temporary download followed by an action and a delete.
if [ x"$2" != x"" ]; then
	tempview "$2" "$1"
	exit $?
fi

# change gophers:// to gopher:// for now.
#if match "$text" '^gophers://'; then
#	text="${text#gophers://}"
#	text="gopher://${text}"
#fi

# gopher protocol plumber
if match "$text" '^(gopher|gophers)://'; then
	filename=$(basename "$text" | sed 's@^\.*@@g')
	mkdir -p "/tmp/gophertmp"
	chmod 700 "/tmp/gophertmp"
	out="/tmp/gophertmp/${filename}"
	gophertype=$(printf '%s' "$text" | \
		sed -E -e 's@^(gopher|gophers)://@@g' -e 's@^[^/]*/?@@g'  | \
		cut -b 1)

	if test "$gophertype" = "" || test "$gophertype" = "1"; then
		sacc "$text"
		exit $?
	fi

	# Download to temp dir and use it's output.
	fetch "$text" > "${out}"

	if test "$gophertype" = "0"; then
		less "$out"
	elif test "$gophertype" = "I"; then
		image "$out"
	elif test "$gophertype" = "g"; then
		movie "$out"
	elif test "$gophertype" = "a" -o "$gophertype" = "s"; then
		audio "$out" # unofficial types used for audio/sound sometimes.
	elif match "$text" '\.(mkv|mp4|m4v|avi|webm|ogg|ogv|gif|gifv|ogm)$' 'i'; then
		movie "$out"
	elif match "$text" '\.(wav|mp3|flac)$' 'i'; then
		audio "$out"
	elif match "$text" '\.(png|jpg|jpeg|webp|bmp)$' 'i'; then
		image "$out"
	fi
elif match "$text" '^(ytdl)://'; then
	text="https://www.youtube.com/embed/${text}"
	movie "$text"
elif match "$text" '^(lbry)://'; then
	text=$("$HOME/.config/scripts/plumb/lbry.sh" "$text")
	movie "$text"
elif match "$text" '^(http|https)://([a-zA-Z0-9]*\.)?wikipedia\.org/'; then
	# open wikipedia always in a browser due to shitty .jpg links with a wrong mime-type.
	www "$text"
elif match "$text" '\.(ogg|mp3)$' 'i'; then
	audio "$text"
elif match "$text" '\.(jpg|png|jpeg)$' 'i'; then
	# download, view in image viewer, then delete.
	tempview image "$text"
elif match "$text" '\.(pdf)$' 'i'; then
	# download, view in pdf viewer, then delete.
	tempview pdf "$text"
elif match "$text" '\.(gifv)$' 'i'; then
	# replace gifv with mp4
	text=$(printf '%s' "$text" | sed 's@gifv$@mp4@')
	movie "$text"
elif match "$text" 'https://docs\.google\.com/document/d' 'i'; then
	# google docs: export document to PDF.
	id=$(printf '%s' "$text" | sed -nE 's@.*https://docs\.google\.com/document/d/([^/]*).*@\1@p')
	if test -n "$id"; then
		# download, view in pdf viewer, then delete.
		text="https://docs.google.com/document/d/$id/export?format=pdf"
		tempview pdf "$text"
	fi
elif match "$text" '^(http|https)://imgur\.com/a/'; then
	# album viewer
	albumid="${text##*/}"
	tmp=$(mktemp)
	"$HOME/.config/scripts/plumb/imgur_album.sh" "$albumid" > "$tmp"
	st -e less "$tmp"
	rm -f "$tmp"
elif match "$text" '^(http|https)://imgur\.com/'; then
	imgid="$(printf '%s' "$text" | sed -E 's@^(http|https)://imgur.com/@@')"
	if test x"$imgid" != x""; then
		text="https://i.imgur.com/$imgid.jpg"
		tempview image "$text"
	else
		www "$text"
	fi
elif match "$text" '://i\.imgur\.com/'; then
	# download, view in image viewer, then delete.
	tempview image "$text"
elif match "$text" '^(http|https)://explosm\.net/comics/[0-9]+/'; then
	# grab direct comic image url.
	# TODO: make this some more generic og:image / og:video function? maybe using "xml2tsv".
	# see: https://ogp.me/
	url=$(fetch "$text" | sed -nE '/<meta property="og:image" content="([^"]*)\?.*">/{ s//\1/;p;q; }')
	test -n "$url" && tempview image "$url"
elif match "$text" '^(http|https)://pastebin\.com/'; then
	# pastebin, always use raw url.
	id="${text##*/}"
	text="https://pastebin.com/raw/${id}"

	# download, view in less, then delete.
	tempview pastebin "$text"
elif match "$text" '^(http|https)://(sprunge\.us|ix\.io|0x0\.st|termbin\.com)/'; then
	# sprunge.us / ix.io: pastebin-like services.
	# download, view in less, then delete.
	tempview pastebin "$text"
elif match "$text" '^(http|https)://.*(\.youtube\.|youtu\.be)'; then
	movie "$text"
elif match "$text" '^(http|https)://.*(\.?twitter\.com)/'; then
	url="${text}"
	url="${url#http://}"
	url="${url#https://}"
	url="${url#www.}"
	url="${url#twitter.com}"
	url="${url#/}"
	# replace with nitter instance.
	url="https://nitter.privacydev.net/${url}"
	www "$url"

	# old twitter status script
#	tmp=$(mktemp)
#	"$HOME/.config/scripts/plumb/twitter_status.sh" "$text" > "$tmp"
#	st -e less "$tmp"
#	rm -f "$tmp"
elif match "$text" '^(http|https)://([^a-z]*\.)?twitch\.tv'; then
	movie "$text"
elif match "$text" '^(http|https)://'; then
	www "$text"
#elif match "$text" '^(magnet):?xt'; then
#	# magnet link.
#	rtorrent "$text"
fi
