; ---- Macros ----

; FRAME pairs, locals — prologue: fp/lr, then `pairs` register pairs from x19 (stored by Lpro<pairs>), then locals.
.macro FRAME pairs, locals=0
	.if (\locals) % 16
	.error "FRAME locals must keep sp 16-byte aligned"
	.endif
	stp	x29, x30, [sp, #-16]!
	.if \pairs
	bl	Lpro\pairs
	.else
	mov	x29, sp
	.endif
	.if (\locals) > 4095
	sub	sp, sp, #((\locals) >> 12), lsl #12
	.endif
	.if (\locals) & 4095
	sub	sp, sp, #((\locals) & 4095)
	.endif
.endm

; ENTRY name — a function called from outside (AppKit, GCD, pthreads): its body Lname runs with x28 = G, x27 = B.
.macro ENTRY name
\name:
	adr	x16, L\name
	b	tramp
L\name:
.endm

; ADDR reg, sym — address of a symbol in this file.
.macro ADDR reg, sym
	adrp	\reg, \sym@PAGE
	add	\reg, \reg, \sym@PAGEOFF
.endm

; CLASS reg, name — an Objective-C class, from the registry.
.macro CLASS reg, name
	ldr	\reg, [x27, #C_\name]
.endm

; SEND / SENDT sel — objc_msgSend with a selector from the registry (SENDT: a tail call).
.macro SEND sel
	ldr	x1, [x27, #\sel]
	bl	_objc_msgSend
.endm
.macro SENDT sel
	ldr	x1, [x27, #\sel]
	b	_objc_msgSend
.endm

; GADDR reg, label — address of a label in G's data, from x28.
.macro GADDR reg, label
	.if (\label - G) < 4096
	add	\reg, x28, #(\label - G)
	.else
	add	\reg, x28, #((\label - G) >> 12), lsl #12
	add	\reg, \reg, #((\label - G) & 4095)
	.endif
.endm

; BADDR reg, offset — address of a B buffer, from x27.
.macro BADDR reg, off
	.if (\off) < 4096
	add	\reg, x27, #(\off)
	.elseif ((\off) & 4095) == 0
	add	\reg, x27, #((\off) >> 12), lsl #12
	.else
	add	\reg, x27, #((\off) >> 12), lsl #12
	add	\reg, \reg, #((\off) & 4095)
	.endif
.endm

; ADDO reg, base, off — reg = base + off, for offsets past an immediate's 4 KiB.
.macro ADDO reg, base, off
	.if (\off) < 4096
	add	\reg, \base, #(\off)
	.else
	add	\reg, \base, #((\off) >> 12), lsl #12
	.if (\off) & 4095
	add	\reg, \reg, #((\off) & 4095)
	.endif
	.endif
.endm

; CSTR reg, text — a C string literal, kept after G.
.macro CSTR reg, text
	.pushsection __TEXT,__cstring,cstring_literals
Lc\@:	.asciz	"\text"
	.popsection
	adrp	\reg, Lc\@@PAGE
	add	\reg, \reg, Lc\@@PAGEOFF
.endm

; LOCK / UNLOCK — the lock guarding the snapshot, the device list and the stream slots.
.macro LOCK
	bl	lock
.endm
.macro UNLOCK
	bl	unlock
.endm

; MAINQ reg — the main dispatch queue.
.macro MAINQ reg
	ldr	\reg, [x27, #F__dispatch_main_q]
.endm

; WORKQ — the global user-initiated queue in x0.
.macro WORKQ
	ldr	x0, [x28, #G_WORKQ]
.endm

; DBL reg, label — a double kept after G.
.macro DBL reg, label
	ldr	\reg, [x28, #(\label - G)]
.endm

; ---- Constants ----

; libcurl.
.equ CURLOPT_WRITEDATA,          10001
.equ CURLOPT_URL,                10002
.equ CURLOPT_RANGE,              10007
.equ CURLOPT_POSTFIELDS,         10015
.equ CURLOPT_USERAGENT,          10018
.equ CURLOPT_HTTPHEADER,         10023
.equ CURLOPT_INTERFACE,          10062
.equ CURLOPT_ACCEPT_ENCODING,    10102
.equ CURLOPT_WRITEFUNCTION,      20011
.equ CURLOPT_FAILONERROR,        45
.equ CURLOPT_FOLLOWLOCATION,     52
.equ CURLOPT_HTTP_VERSION,       84
.equ CURLOPT_BUFFERSIZE,         98
.equ CURLOPT_NOSIGNAL,           99
.equ CURLOPT_TIMEOUT_MS,         155
.equ CURLOPT_CONNECTTIMEOUT_MS,  156
.equ CURL_HTTP_VERSION_1_1,      2
.equ CURL_GLOBAL_ALL,            3
.equ CURLINFO_RESPONSE_CODE,     0x200002
.equ CURLINFO_CONTENT_TYPE,      0x100012
.equ CURLINFO_EFFECTIVE_URL,     0x100001
.equ CURLOPT_SHARE,              10100
.equ CURLSHOPT_SHARE,            1
.equ CURLSHOPT_LOCKFUNC,         3
.equ CURLSHOPT_UNLOCKFUNC,       4
.equ CURL_LOCK_DATA_DNS,         3
.equ CURL_LOCK_DATA_SSL_SESSION, 4
.equ CURL_LOCK_DATA_CONNECT,     5
.equ CURLH_HEADER,               1

; BSD sockets, signals and GCD.
.equ AF_INET,                    2
.equ SOCK_STREAM,                1
.equ SOCK_DGRAM,                 2
.equ IPPROTO_IP,                 0
.equ IP_MULTICAST_IF,            9
.equ SOL_SOCKET,                 0xffff
.equ SO_RCVTIMEO,                0x1006
.equ SOCKADDR_IN_HEAD,           0x0210   ; sin_len = 16, sin_family = AF_INET
.equ SIGPIPE,                    13
.equ SIG_IGN,                    1
.equ QOS_CLASS_USER_INITIATED,   0x19
.equ DISPATCH_TIME_FOREVER,      -1
.equ IFA_NAME,                   8
.equ IFA_FLAGS,                  16
.equ IFA_ADDR,                   24
.equ IFA_NETMASK,                32

; Network timeouts and limits.
.equ SSDP_PORT_BE,               0x6c07   ; htons(1900)
.equ SSDP_ROUNDS,                3
.equ SSDP_WAIT_MS,               800
.equ SSDP_MAX_REPLIES,           32
.equ SOAP_TIMEOUT_MS,            5000
.equ DESC_TIMEOUT_MS,            2500
.equ CONNECT_TIMEOUT_MS,         1500
.equ ART_TIMEOUT_MS,             10000
.equ API_TIMEOUT_MS,             30000
.equ API_CONNECT_MS,             8000
.equ BUF_MAX,                    0x800000 ; 8 MiB cap for any buffered body
.equ REQ_MAX,                    4096
.equ PROXY_BUFFER,               65536
.equ CHUNK,                      0xa00000 ; 10 MiB: larger upstream ranges are throttled to realtime
.equ CLIENT_TIMEOUT_S,           10
.equ ACCEPT_BACKOFF_US,          10000
.equ MAX_CONNS,                  32
.equ LIVE_TRIES,                 3        ; failed segment fetches in a row before a live stream ends
.equ SLOTS,                      32       ; a video on This Mac takes five: picture, sound and their playlists
.equ TOKEN_STRIDE,               40       ; 32 hex + NUL; the last byte flags a live stream
.equ SLOT_SOUND,                 0        ; what a stream slot serves
.equ SLOT_LIVE,                  1        ; a live broadcast, as ADTS
.equ SLOT_VIDEO,                 2
.equ MYURI_SIZE,                 4096
.equ HIDE_TICKS,                 3        ; idle seconds before the controls leave a playing video
.equ VIDEO_MAX_H,                2160     ; the tallest video stream picked
.equ SKIP_SECONDS,               10
.equ VOLUME_STEP,                5

; Transport states.
.equ ST_OFFLINE,                 0
.equ ST_STOPPED,                 1
.equ ST_PLAYING,                 2
.equ ST_PAUSED,                  3
.equ ST_TRANSITIONING,           4

; now: the "now playing" snapshot shared with the main thread.
.equ NOW_STATE,                  0
.equ NOW_SEL,                    4
.equ NOW_VOL,                    8
.equ NOW_MUTE,                   12
.equ NOW_POS,                    16
.equ NOW_DUR,                    24       ; 0 = unknown or live
.equ NOW_NAME,                   32       ; char[128]
.equ NOW_TITLE,                  160      ; char[512]
.equ NOW_ARTIST,                 672      ; char[256]
.equ NOW_ART,                    928      ; char[2048]
.equ NOW_DEVREV,                 2976
.equ NOW_SIZE,                   2992

; Track: title, artist and artwork URL, laid out as in the snapshot from NOW_TITLE.
.equ T_TITLE,                    0        ; char[512]
.equ T_ARTIST,                   512      ; char[256]
.equ T_ART,                      768      ; char[2048]
.equ T_SIZE,                     2816

; Fmt: what HLS needs of a YouTube stream.
.equ FMT_INIT,                   0        ; last byte of the init segment
.equ FMT_IDX0,                   8        ; first and last byte of the segment index (sidx)
.equ FMT_IDX1,                   16
.equ FMT_RATE,                   24       ; bits per second
.equ FMT_CODECS,                 32       ; char[64], e.g. "avc1.640028"
.equ FMT_SIZE,                   96

; Play job: main -> worker -> device queue -> main.
.equ JOB_QUERY,                  0        ; char*, a link, search text or file path (owned)
.equ JOB_RESULT,                 8        ; int, PLAY_*
.equ JOB_LIVE,                   12       ; int
.equ JOB_DUR,                    16       ; seconds, 0 when live or unknown
.equ JOB_ERR,                    24       ; char*, why it failed, or NULL
.equ JOB_KIND,                   32       ; int, KIND_*
.equ JOB_ITEM,                   40       ; AVPlayerItem for This Mac, retained, or nil
.equ JOB_TRACK,                  48       ; Track
.equ JOB_AFMT,                   JOB_TRACK + T_SIZE ; Fmt of the sound stream
.equ JOB_VFMT,                   JOB_AFMT + FMT_SIZE ; and of the picture stream
.equ JOB_MSG,                    JOB_VFMT + FMT_SIZE ; char[128], an error message
.equ JOB_URL,                    JOB_MSG + 128      ; char[4096], the media URL
.equ JOB_VURL,                   JOB_URL + 4096     ; char[4096], the video stream's URL, or ""
.equ JOB_MURL,                   JOB_VURL + 4096    ; char[4096], picture and sound in one MP4 (for TVs), or ""
.equ JOB_LOCAL,                  JOB_MURL + 4096    ; char[256], This Mac's URL of the sound
.equ JOB_VLOCAL,                 JOB_LOCAL + 256    ; char[256], and of the picture, or ""
.equ JOB_HLS,                    JOB_VLOCAL + 256   ; char[256], the HLS presentation of both, or ""
.equ JOB_HLSA,                   JOB_HLS + 256      ; char[256], its sound alone, or ""
.equ JOB_SIZE,                   JOB_HLSA + 256
.equ KIND_YOUTUBE,               0        ; a YouTube link or search
.equ KIND_WEB,                   1        ; any other web address, played as it is
.equ KIND_FILE,                  2        ; a file on this Mac (JOB_QUERY is its path)
.equ PLAY_OK,                    0
.equ PLAY_FAILED,                1
.equ PLAY_REJECTED,              2

; Device list entries; entry 0 is This Mac.
.equ DEV_NAME,                   0
.equ DEV_BASE,                   128
.equ DEV_AVT,                    256
.equ DEV_RC,                     512
.equ DEV_VIDEO,                  768      ; byte: 1 it renders video (a TV), 2 it plays HLS
.equ DEV_SIZE,                   776
.equ MAX_DEVS,                   16
.equ AVPLAYER_WAITING,           1
.equ AVPLAYER_PLAYING,           2

; Stream proxy state for the libcurl write callback.
.equ PX_FD,                      0
.equ PX_BROKEN,                  4
.equ PX_SENT,                    8
.equ PX_HEAD,                    12
.equ PX_RANGED,                  16
.equ PX_CHECKED,                 20
.equ PX_POS,                     24       ; next byte (negative: a suffix range)
.equ PX_END,                     32
.equ PX_CURL,                    40
.equ PX_SIZE,                    48

; AppKit.
.equ WIN_STYLE,                  0x800f   ; titled|closable|miniaturizable|resizable|fullSizeContentView
.equ NSEventTypeLeftMouseDown,   1
.equ NSEventTypeLeftMouseDragged, 6
.equ FULL_SCREEN_PRIMARY,        128
.equ TRACK_OPTIONS,              0x282    ; mouse moved, always active, in the visible rect
.equ PLAYER_ITEM_FAILED,         2

; Autoresizing: which margins or sizes follow the window.
.equ AR_LEFT,                    1
.equ AR_WIDTH,                   2
.equ AR_RIGHT,                   4
.equ AR_BOTTOM,                  8
.equ AR_HEIGHT,                  16
.equ AR_TOP,                     32

; Window layout in points: views are built for the smallest window (from the content's top-left; inside a container, from its bottom-left), then follow it.
.equ WIN_W,                      640
.equ WIN_H,                      400
.equ START_W,                    880
.equ START_H,                    560
.equ BAR_M,                      12       ; the control bar floats this far from the edges
.equ BAR_W,                      WIN_W - 2 * BAR_M
.equ BAR_H,                      96
.equ STAGE_B,                    BAR_M + BAR_H + 16 ; artwork and empty state sit between the bar
.equ STAGE_T,                    40       ; and the title bar
.equ ART_RADIUS,                 14
.equ ART_MAX,                    720
.equ SPIN_S,                     32
.equ EMPTY_W,                    420
.equ EMPTY_H,                    196
.equ PILL_W,                     132
.equ PILL_H,                     32
.equ URL_W,                      520
.equ URL_H,                      48
.equ STATUS_T,                   36
.equ LABEL_H,                    16
.equ SLIDER_H,                   20
.equ TIME_W,                     52
.equ ROW1_Y,                     BAR_H - 12 - SLIDER_H ; position slider
.equ ROW2_C,                     34       ; middle of the second row
.equ PLAY_S,                     44
.equ BTN_S,                      32
.equ ICON_S,                     24
.equ BTN_GAP,                    14
.equ PLAY_X,                     BAR_W / 2 - PLAY_S / 2
.equ BACK_X,                     PLAY_X - BTN_GAP - BTN_S
.equ FWD_X,                      PLAY_X + PLAY_S + BTN_GAP
.equ DEV_W,                      40
.equ DEV_X,                      BAR_W - 12 - DEV_W
.equ AIR_W,                      28
.equ AIR_X,                      DEV_X - 4 - AIR_W
.equ VOL_W,                      64
.equ VOL_X,                      AIR_X - 8 - VOL_W
.equ MUTE_X,                     VOL_X - 4 - ICON_S
.equ AO_X,                       MUTE_X - 12 - ICON_S
.equ TEXT_W,                     BACK_X - 32

; UI timing, in timer ticks (one per second).
.equ STATUS_TICKS,               6
.equ HOLD_TICKS,                 2

; G: scalars at fixed offsets from x28; string literals follow them.
.equ G_APP,                      0
.equ G_CTRL,                     8
.equ G_QUEUE,                    16       ; serial device queue
.equ G_CURL,                     24       ; device queue's keep-alive handle
.equ G_PLAYER,                   32       ; AVPlayer
.equ G_LAN,                      40       ; mask << 32 | address, network order, one atomic word
.equ G_LOCK,                     48       ; os_unfair_lock
.equ G_PORT,                     52       ; proxy port
.equ G_DEVN,                     56       ; devices listed (lock)
.equ G_CHOSE,                    60       ; a device was picked by hand (device queue)
.equ G_POLLB,                    64       ; a poll is queued (atomic)
.equ G_VOLB,                     68       ; a volume change is queued (atomic)
.equ G_PVOL,                     72       ; latest slider volume (atomic)
.equ G_DISC,                     76       ; searches running, a bit per kind (atomic)
.equ G_SLOTI,                    80       ; next stream slot (lock)
.equ G_MYDUR,                    88       ; duration we sent to the device (device queue)
.equ G_LTDUR,                    96       ; This Mac's duration (main)
.equ G_TICK,                     104      ; timer ticks since launch
.equ G_SEEKH,                    112      ; tick until which polled positions are ignored
.equ G_VOLH,                     120      ; tick until which polled volumes are ignored
.equ G_MSGT,                     128      ; tick after which the status message expires
.equ G_ARTGEN,                   136      ; artwork request generation
.equ G_SEL,                      144      ; selected device, as the UI routes it
.equ G_DEVREV,                   148      ; device list revision in the picker
.equ G_READY,                    152      ; the device answers
.equ G_LOADING,                  156      ; a link is being resolved
.equ G_PPSHOWN,                  160      ; play/pause shows "pause"
.equ G_MUTESHOWN,                164
.equ G_SEEKDRAG,                 168
.equ G_VOLDRAG,                  172
.equ G_MSGERR,                   176      ; the status message is an error
.equ G_AONLY,                    180      ; Audio Only: no picture is fetched or shown
.equ G_WIN,                      184      ; views and images (main thread)
.equ G_CONTENT,                  192
.equ G_FIELD,                    200      ; the link field of Open from URL
.equ G_SPIN,                     208
.equ G_ART,                      216
.equ G_TITLE,                    224
.equ G_ARTIST,                   232
.equ G_CUR,                      240
.equ G_DUR,                      248
.equ G_BACK,                     256      ; enabled when seekable: back, forward, position
.equ G_FWD,                      264
.equ G_POS,                      272
.equ G_PP,                       280      ; enabled when the device answers: play, mute, volume
.equ G_MUTE,                     288
.equ G_VOL,                      296
.equ G_VIDEO,                    304      ; the view of This Mac's picture
.equ G_STATUS,                   312
.equ G_DEV,                      320
.equ G_IMGPLAY,                  328
.equ G_IMGPAUSE,                 336
.equ G_IMGMUTED,                 344
.equ G_IMGUNMUTED,               352
.equ G_SLOTURL,                  360      ; char*[SLOTS], media URLs or file paths (lock)
.equ G_SECOND,                   G_SLOTURL + 8 * SLOTS ; colors (main)
.equ G_TEXT,                     G_SECOND + 8
.equ G_YEL,                      G_TEXT + 8
.equ G_RED,                      G_YEL + 8
.equ G_BGC,                      G_RED + 8
.equ G_SURF,                     G_BGC + 8
.equ G_SURF2,                    G_SURF + 8
.equ G_T0,                       G_SURF2 + 8 ; scratch objects of the UI programs
.equ G_T1,                       G_T0 + 8
.equ G_T2,                       G_T1 + 8
.equ G_T3,                       G_T2 + 8
.equ G_WORKQ,                    G_T3 + 8 ; the global user-initiated queue
.equ G_BAR,                      G_WORKQ + 8 ; the control bar
.equ G_EMPTY,                    G_BAR + 8 ; what shows when nothing is playing
.equ G_URLBOX,                   G_EMPTY + 8 ; Open from URL's floating field
.equ G_AOBTN,                    G_URLBOX + 8 ; the Audio Only button and menu item
.equ G_AOITEM,                   G_AOBTN + 8
.equ G_IMGDEV,                   G_AOITEM + 8 ; the picker's face: This Mac, then a device
.equ G_IMGDEVON,                 G_IMGDEV + 8
.equ G_ARTASP,                   G_IMGDEVON + 8 ; the artwork's height / width (double)
.equ G_IDLE,                     G_ARTASP + 8 ; ticks since the mouse last moved
.equ G_HASVIDEO,                 G_IDLE + 4 ; This Mac's media has a picture
.equ G_BARHID,                   G_HASVIDEO + 4 ; the bar is faded out
.equ G_HOVER,                    G_BARHID + 4 ; the mouse is over the bar
.equ G_ARTOK,                    G_HOVER + 4 ; the artwork has an image
.equ G_FAILED,                   G_ARTOK + 4 ; This Mac's item failed and it was reported
.equ G_DEVON,                    G_FAILED + 4 ; the picker's face shows a device
.equ G_AV1,                      G_DEVON + 4 ; AV1 decodes in hardware
.equ G_NOTE,                     G_AV1 + 4 ; the artwork card's music note, shown without an image
.equ G_RESUMEMS,                 G_NOTE + 8 ; Audio Only's swap: the moment to return to
.equ G_RESUMET,                  G_RESUMEMS + 8 ; and the timer waiting for the new item, or nil
.equ G_RESUMEPLAY,               G_RESUMET + 8 ; it was playing
.equ G_RATE,                     G_RESUMEPLAY + 8 ; Playback > Speed (float)
.equ G_SUBMENU,                  G_RATE + 8 ; View > Subtitles
.equ G_PIP,                      G_SUBMENU + 8 ; the Picture in Picture controller, made on first use
.equ G_TV,                       G_PIP + 8 ; the selected device's DEV_VIDEO
.equ G_SHARE,                    G_TV + 8 ; the libcurl pool
.equ G_SHLOCKS,                  G_SHARE + 8 ; its locks, one per kind of data (os_unfair_lock[8])
.equ G_CONNS,                    G_SHLOCKS + 32
.equ G_SIZE,                     G_CONNS + 8

; ---- Data ----

	.section __DATA,__data
	.p2align 3
G:	.space	G_SIZE
Lf_100:	.float	100.0                     ; volume percent, 8-aligned after G
	.float	0.0

; XML entities, 8 bytes each: the character, then its name after '&' (zero-padded).
Lxml_entities:
	.ascii	"&amp;\0\0\0"
	.ascii	"<lt;\0\0\0\0"
	.ascii	">gt;\0\0\0\0"
	.ascii	"\"quot;\0\0"
	.ascii	"'apos;\0\0"
	.ascii	"'#39;\0\0\0"             ; numeric form, decode only
	.byte	0

; B: the large buffers, at fixed offsets from x27.
.equ B_LANIP,                    0        ; char[16], LAN address as text (device queue)
.equ B_CUR,                      16       ; selected device (device queue)
.equ B_NOW,                      B_CUR + DEV_SIZE + 8 ; snapshot (lock)
.equ B_MYTRACK,                  4096     ; and its track
	.if B_NOW + NOW_SIZE > B_MYTRACK
	.error "B_NOW overlaps"
	.endif
.equ B_SLOTTOK,                  6912     ; stream tokens (lock)
.equ B_UIMSG,                    B_SLOTTOK + SLOTS * TOKEN_STRIDE ; char[256], status message (main)
.equ B_UIARTIST,                 B_UIMSG + 256 ; char[256], last rendered artist (main)
.equ B_UIART,                    B_UIARTIST + 256 ; char[2048], artwork shown or loading (main)
.equ B_UITITLE,                  B_UIART + 2048 ; char[512], last rendered title (main)
.equ B_LTAURL,                   B_UITITLE + 512 ; char[256], This Mac's sound stream (main)
.equ B_LTTRACK,                  12288    ; This Mac's track (main)
	.if B_LTAURL + 256 > B_LTTRACK
	.error "B buffers overlap"
	.endif
.equ B_DEVS,                     B_LTTRACK + T_SIZE ; device list (lock)
.equ B_REG,                      (B_DEVS + MAX_DEVS * DEV_SIZE + 4095) & ~4095 ; the registry, 4 KiB-aligned: one add reaches it

; A search's handoff from its worker to the device queue, one per kind, after the registry.
.equ SC_MODE,                    0        ; 0 rebuilds the list, 1 only adds to it
.equ SC_COUNT,                   4
.equ SC_LOCS,                    8        ; char[MAX_DEVS - 1][256], description URLs
.equ SC_SIZE,                    SC_LOCS + (MAX_DEVS - 1) * 256

; SYM / OBJC name — an imported symbol / class in the registry (FN, defined with each pass, is a function called by name).
.macro SYM name
	REG	F_\name, "\name"
.endm
.macro OBJC name
	REG	C_\name, "OBJC_CLASS_$_\name"
.endm

; REGISTRY — imported symbols, classes, then selectors, looked up by name once at launch into B.
.macro REGISTRY
	FN	accept
	FN	arc4random_buf
	FN	arc4random_uniform
	FN	asprintf
	FN	bind
	FN	calloc
	FN	close
	FN	curl_easy_cleanup
	FN	curl_easy_getinfo
	FN	curl_easy_header
	FN	curl_easy_init
	FN	curl_easy_perform
	FN	curl_easy_reset
	FN	curl_easy_setopt
	FN	curl_share_init
	FN	curl_share_setopt
	FN	curl_slist_append
	FN	curl_slist_free_all
	FN	dispatch_async_f
	FN	dispatch_semaphore_create
	FN	dispatch_semaphore_signal
	FN	dispatch_semaphore_wait
	FN	dispatch_sync_f
	FN	free
	FN	freeifaddrs
	FN	getenv
	FN	getifaddrs
	FN	getsockname
	FN	inet_ntop
	FN	listen
	FN	lseek
	FN	malloc
	FN	memcpy
	FN	objc_autoreleasePoolPop
	FN	objc_autoreleasePoolPush
	FN	objc_msgSend
	FN	open
	FN	os_unfair_lock_lock
	FN	os_unfair_lock_unlock
	FN	pthread_create
	FN	pthread_detach
	FN	realloc
	FN	recv
	FN	sel_registerName
	FN	sendfile
	FN	sendto
	FN	setsockopt
	FN	snprintf
	FN	socket
	FN	sscanf
	FN	strcasecmp
	FN	strcasestr
	FN	strchr
	FN	strcmp
	FN	strcspn
	FN	strdup
	FN	strlcpy
	FN	strlen
	FN	strncmp
	FN	strrchr
	FN	strstr
	FN	strtol
	FN	usleep
	FN	write
	SYM	NSFontWeightMedium
	SYM	NSFontWeightRegular
	SYM	NSFontWeightSemibold
	SYM	VTIsHardwareDecodeSupported
	SYM	_dispatch_main_q
	SYM	class_addMethod
	SYM	curl_global_init
	SYM	dispatch_get_global_queue
	SYM	dispatch_queue_attr_make_with_qos_class
	SYM	dispatch_queue_create
	SYM	objc_allocateClassPair
	SYM	objc_registerClassPair
	SYM	signal
	OBJC	AVPlayer
	OBJC	AVPlayerItem
	OBJC	AVPictureInPictureController
	OBJC	AVPlayerLayer
	OBJC	AVRoutePickerView
	OBJC	CALayer
	OBJC	NSAppearance
	OBJC	NSApplication
	OBJC	NSArray
	OBJC	NSButton
	OBJC	NSCharacterSet
	OBJC	NSColor
	OBJC	NSCursor
	OBJC	NSData
	OBJC	NSFont
	OBJC	NSImage
	OBJC	NSImageSymbolConfiguration
	OBJC	NSImageView
	OBJC	NSJSONSerialization
	OBJC	NSMenu
	OBJC	NSMenuItem
	OBJC	NSObject
	OBJC	NSOpenPanel
	OBJC	NSPopUpButton
	OBJC	NSProgressIndicator
	OBJC	NSSlider
	OBJC	NSString
	OBJC	NSTextField
	OBJC	NSTimer
	OBJC	NSTrackingArea
	OBJC	NSURL
	OBJC	NSView
	OBJC	NSWindow
	OBJC	UTType
	REGSEL
	REG	S_systemFontOfSize_weight_, "systemFontOfSize:weight:"
	REG	S_monospacedDigitSystemFontOfSize_weight_, "monospacedDigitSystemFontOfSize:weight:"
	REG	S_JSONObjectWithData_options_error_, "JSONObjectWithData:options:error:"
	REG	S_URLWithString_, "URLWithString:"
	REG	S_UTF8String, "UTF8String"
	REG	S_CGColor, "CGColor"
	REG	S_URL, "URL"
	REG	S_URLByDeletingPathExtension, "URLByDeletingPathExtension"
	REG	S_absoluteString, "absoluteString"
	REG	S_activate, "activate"
	REG	S_addItem_, "addItem:"
	REG	S_addItemWithTitle_action_keyEquivalent_, "addItemWithTitle:action:keyEquivalent:"
	REG	S_addSubview_, "addSubview:"
	REG	S_addTrackingArea_, "addTrackingArea:"
	REG	S_alloc, "alloc"
	REG	S_animator, "animator"
	REG	S_appearanceNamed_, "appearanceNamed:"
	REG	S_arrayWithObject_, "arrayWithObject:"
	REG	S_assetTrack, "assetTrack"
	REG	S_bounds, "bounds"
	REG	S_buttonWithImage_target_action_, "buttonWithImage:target:action:"
	REG	S_buttonWithTitle_target_action_, "buttonWithTitle:target:action:"
	REG	S_cancelOperation_, "cancelOperation:"
	REG	S_cell, "cell"
	REG	S_center, "center"
	REG	S_clickCount, "clickCount"
	REG	S_colorWithSRGBRed_green_blue_alpha_, "colorWithSRGBRed:green:blue:alpha:"
	REG	S_componentsSeparatedByString_, "componentsSeparatedByString:"
	REG	S_configurationWithPaletteColors_, "configurationWithPaletteColors:"
	REG	S_configurationWithPointSize_weight_, "configurationWithPointSize:weight:"
	REG	S_currentEvent, "currentEvent"
	REG	S_currentItem, "currentItem"
	REG	S_currentTime, "currentTime"
	REG	S_dataWithBytes_length_, "dataWithBytes:length:"
	REG	S_dataWithBytesNoCopy_length_freeWhenDone_, "dataWithBytesNoCopy:length:freeWhenDone:"
	REG	S_doubleValue, "doubleValue"
	REG	S_draggingPasteboard, "draggingPasteboard"
	REG	S_duration, "duration"
	REG	S_fileURLWithPath_, "fileURLWithPath:"
	REG	S_firstObject, "firstObject"
	REG	S_host, "host"
	REG	S_imageViewWithImage_, "imageViewWithImage:"
	REG	S_imageWithSymbolConfiguration_, "imageWithSymbolConfiguration:"
	REG	S_imageWithSystemSymbolName_accessibilityDescription_, "imageWithSystemSymbolName:accessibilityDescription:"
	REG	S_indexOfSelectedItem, "indexOfSelectedItem"
	REG	S_initWithContentRect_styleMask_backing_defer_, "initWithContentRect:styleMask:backing:defer:"
	REG	S_initWithData_, "initWithData:"
	REG	S_initWithFrame_, "initWithFrame:"
	REG	S_initWithFrame_pullsDown_, "initWithFrame:pullsDown:"
	REG	S_initWithRect_options_owner_userInfo_, "initWithRect:options:owner:userInfo:"
	REG	S_initWithTitle_, "initWithTitle:"
	REG	S_intValue, "intValue"
	REG	S_isEnabled, "isEnabled"
	REG	S_isEqualToString_, "isEqualToString:"
	REG	S_isFileURL, "isFileURL"
	REG	S_isMuted, "isMuted"
	REG	S_itemAtIndex_, "itemAtIndex:"
	REG	S_labelWithString_, "labelWithString:"
	REG	S_lastPathComponent, "lastPathComponent"
	REG	S_layer, "layer"
	REG	S_locationInWindow, "locationInWindow"
	REG	S_makeFirstResponder_, "makeFirstResponder:"
	REG	S_makeKeyAndOrderFront_, "makeKeyAndOrderFront:"
	REG	S_maxValue, "maxValue"
	REG	S_mediaType, "mediaType"
	REG	S_menu, "menu"
	REG	S_new, "new"
	REG	S_numberOfItems, "numberOfItems"
	REG	S_openPanel, "openPanel"
	REG	S_path, "path"
	REG	S_pause, "pause"
	REG	S_play, "play"
	REG	S_playerItemWithURL_, "playerItemWithURL:"
	REG	S_playerLayerWithPlayer_, "playerLayerWithPlayer:"
	REG	S_presentationSize, "presentationSize"
	REG	S_readObjectsForClasses_options_, "readObjectsForClasses:options:"
	REG	S_registerForDraggedTypes_, "registerForDraggedTypes:"
	REG	S_release, "release"
	REG	S_removeItemAtIndex_, "removeItemAtIndex:"
	REG	S_replaceCurrentItemWithPlayerItem_, "replaceCurrentItemWithPlayerItem:"
	REG	S_retain, "retain"
	REG	S_run, "run"
	REG	S_runModal, "runModal"
	REG	S_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_, "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"
	REG	S_seekToTime_toleranceBefore_toleranceAfter_, "seekToTime:toleranceBefore:toleranceAfter:"
	REG	S_selectText_, "selectText:"
	REG	S_separatorItem, "separatorItem"
	REG	S_setAction_, "setAction:"
	REG	S_setActivationPolicy_, "setActivationPolicy:"
	REG	S_setAlignment_, "setAlignment:"
	REG	S_setAllowedContentTypes_, "setAllowedContentTypes:"
	REG	S_setAlphaValue_, "setAlphaValue:"
	REG	S_setAppearance_, "setAppearance:"
	REG	S_setArrowPosition_, "setArrowPosition:"
	REG	S_setAutoresizingMask_, "setAutoresizingMask:"
	REG	S_setBackgroundColor_, "setBackgroundColor:"
	REG	S_setBezeled_, "setBezeled:"
	REG	S_setBordered_, "setBordered:"
	REG	S_setClipsToBounds_, "setClipsToBounds:"
	REG	S_setCollectionBehavior_, "setCollectionBehavior:"
	REG	S_setContentMinSize_, "setContentMinSize:"
	REG	S_setContentSize_, "setContentSize:"
	REG	S_setContentTintColor_, "setContentTintColor:"
	REG	S_setContents_, "setContents:"
	REG	S_setContentsGravity_, "setContentsGravity:"
	REG	S_setContentsRect_, "setContentsRect:"
	REG	S_setControlSize_, "setControlSize:"
	REG	S_setCornerCurve_, "setCornerCurve:"
	REG	S_setCornerRadius_, "setCornerRadius:"
	REG	S_setDelegate_, "setDelegate:"
	REG	S_setDisplayedWhenStopped_, "setDisplayedWhenStopped:"
	REG	S_setDoubleValue_, "setDoubleValue:"
	REG	S_setDrawsBackground_, "setDrawsBackground:"
	REG	S_setEnabled_, "setEnabled:"
	REG	S_setFocusRingType_, "setFocusRingType:"
	REG	S_setFont_, "setFont:"
	REG	S_setFrame_, "setFrame:"
	REG	S_setFrameOrigin_, "setFrameOrigin:"
	REG	S_setHidden_, "setHidden:"
	REG	S_setHiddenUntilMouseMoves_, "setHiddenUntilMouseMoves:"
	REG	S_setImage_, "setImage:"
	REG	S_setKeyEquivalentModifierMask_, "setKeyEquivalentModifierMask:"
	REG	S_setLayer_, "setLayer:"
	REG	S_setLineBreakMode_, "setLineBreakMode:"
	REG	S_setMainMenu_, "setMainMenu:"
	REG	S_setMaxValue_, "setMaxValue:"
	REG	S_setMovableByWindowBackground_, "setMovableByWindowBackground:"
	REG	S_setMuted_, "setMuted:"
	REG	S_setPlaceholderString_, "setPlaceholderString:"
	REG	S_setScrollable_, "setScrollable:"
	REG	S_setState_, "setState:"
	REG	S_setStringValue_, "setStringValue:"
	REG	S_setStyle_, "setStyle:"
	REG	S_setSubmenu_, "setSubmenu:"
	REG	S_setSymbolConfiguration_, "setSymbolConfiguration:"
	REG	S_setTarget_, "setTarget:"
	REG	S_setTextColor_, "setTextColor:"
	REG	S_setTitle_, "setTitle:"
	REG	S_setTitleVisibility_, "setTitleVisibility:"
	REG	S_setTitlebarAppearsTransparent_, "setTitlebarAppearsTransparent:"
	REG	S_setTolerance_, "setTolerance:"
	REG	S_setToolTip_, "setToolTip:"
	REG	S_setTrackFillColor_, "setTrackFillColor:"
	REG	S_setUsesSingleLineMode_, "setUsesSingleLineMode:"
	REG	S_setVolume_, "setVolume:"
	REG	S_setWantsLayer_, "setWantsLayer:"
	REG	S_setWindowsMenu_, "setWindowsMenu:"
	REG	S_sharedApplication, "sharedApplication"
	REG	S_startAnimation_, "startAnimation:"
	REG	S_status, "status"
	REG	S_stopAnimation_, "stopAnimation:"
	REG	S_stringByTrimmingCharactersInSet_, "stringByTrimmingCharactersInSet:"
	REG	S_stringForType_, "stringForType:"
	REG	S_stringValue, "stringValue"
	REG	S_stringWithUTF8String_, "stringWithUTF8String:"
	REG	S_timeControlStatus, "timeControlStatus"
	REG	S_toggleFullScreen_, "toggleFullScreen:"
	REG	S_tracks, "tracks"
	REG	S_type, "type"
	REG	S_typeWithIdentifier_, "typeWithIdentifier:"
	REG	S_volume, "volume"
	REG	S_whitespaceAndNewlineCharacterSet, "whitespaceAndNewlineCharacterSet"
	REG	S_count, "count"
	REG	S_isHidden, "isHidden"
	REG	S_setPlayer_, "setPlayer:"
	REG	S_setRoutePickerButtonBordered_, "setRoutePickerButtonBordered:"
	REG	S_setRoutePickerButtonColor_forState_, "setRoutePickerButtonColor:forState:"
	REG	S_initWithPlayerLayer_, "initWithPlayerLayer:"
	REG	S_isPictureInPictureActive, "isPictureInPictureActive"
	REG	S_startPictureInPicture, "startPictureInPicture"
	REG	S_stopPictureInPicture, "stopPictureInPicture"
	REG	S_keyCode, "keyCode"
	REG	S_styleMask, "styleMask"
	REG	S_tag, "tag"
	REG	S_setTag_, "setTag:"
	REG	S_itemArray, "itemArray"
	REG	S_removeAllItems, "removeAllItems"
	REG	S_options, "options"
	REG	S_displayName, "displayName"
	REG	S_asset, "asset"
	REG	S_mediaSelectionGroupForMediaCharacteristic_, "mediaSelectionGroupForMediaCharacteristic:"
	REG	S_currentMediaSelection, "currentMediaSelection"
	REG	S_selectedMediaOptionInMediaSelectionGroup_, "selectedMediaOptionInMediaSelectionGroup:"
	REG	S_selectMediaOption_inMediaSelectionGroup_, "selectMediaOption:inMediaSelectionGroup:"
	REG	S_setDefaultRate_, "setDefaultRate:"
	REG	S_setRate_, "setRate:"
	REG	S_act_option_, "act_option:"
	REG	S_invalidate, "invalidate"
	REG	S_itemTitleAtIndex_, "itemTitleAtIndex:"
	REG	S_objectAtIndex_, "objectAtIndex:"
	REG	S_setContentView_, "setContentView:"
	REG	S_size, "size"
	REG	S_sliderWithTarget_action_, "sliderWithTarget:action:"
.endm
.set Lnreg, 0
.macro REG sym, name
	.set	\sym, B_REG + 8 * Lnreg
	.set	Lnreg, Lnreg + 1
.endm
.macro REGSEL
	.set	B_SEL, B_REG + 8 * Lnreg      ; the first selector
.endm
.macro FN name                            ; its stub jumps through the slot
	REG	F_\name, "\name"
	.pushsection __TEXT,__text,regular,pure_instructions
_\name:
	ldr	x16, [x27, #F_\name]
	br	x16
	.popsection
.endm
	REGISTRY
	.purgem	REG
	.purgem	REGSEL
	.purgem	FN
.equ B_SCAN,                     B_REG + 8 * Lnreg
.equ B_MYURI,                    B_SCAN + 2 * SC_SIZE ; char[MYURI_SIZE], what we last sent to the device (device queue)
.equ B_LTVURL,                   B_MYURI + MYURI_SIZE ; char[4096], This Mac's picture: our HLS or a broadcast's own, or "" (main)
.equ B_VISITOR,                  B_LTVURL + 4096 ; char[288], the visitorData member once YouTube gave it (worker)
.equ B_SIZE,                     B_VISITOR + 288
	.lcomm	B, B_SIZE, 4

	.text

; ---- Frames and entry ----

; Lpro<n> — the rest of a FRAME prologue: frame pointer, room for n register pairs below it, and the pairs.
	.p2align 2
Lpro4:
	mov	x29, sp
	sub	sp, sp, #64
	stp	x25, x26, [x29, #-64]
	b	Lsave3
Lpro3:
	mov	x29, sp
	sub	sp, sp, #48
Lsave3:
	stp	x23, x24, [x29, #-48]
	b	Lsave2
Lpro2:
	mov	x29, sp
	sub	sp, sp, #32
Lsave2:
	stp	x21, x22, [x29, #-32]
	b	Lsave1
Lpro1:
	mov	x29, sp
	sub	sp, sp, #16
Lsave1:
	stp	x19, x20, [x29, #-16]
	ret

; Lret<n> — epilogue of a FRAME with n pairs.
Lret4:
	ldp	x25, x26, [x29, #-64]
Lret3:
	ldp	x23, x24, [x29, #-48]
Lret2:
	ldp	x21, x22, [x29, #-32]
Lret1:
	ldp	x19, x20, [x29, #-16]
Lret0:
	mov	sp, x29
	ldp	x29, x30, [sp], #16
	ret

; tramp — run x16 with x28 = G and x27 = B, keeping the caller's.
tramp:
	stp	x27, x28, [sp, #-32]!
	str	x30, [sp, #16]
	ADDR	x28, G
	ADDR	x27, B
	blr	x16
	ldr	x30, [sp, #16]
	ldp	x27, x28, [sp], #32
	ret

; Strings used in more than one place.
	.pushsection __DATA,__data
Ls_slash:	.asciz	"/"               ; Ls_slash+1 is ""
Ls_crlf:	.asciz	"\r\n"
Ls_sep:	.asciz	"://"
Ls_avt:	.asciz	"AVTransport"
Ls_rc:	.asciz	"RenderingControl"
Ls_master:	.asciz	"<Channel>Master</Channel>"
Ls_play:	.asciz	"Play"
Ls_speed:	.asciz	"<Speed>1</Speed>"
Ls_setmute:	.asciz	"SetMute"
Ls_stream:	.asciz	"/stream/"
Ls_mp4:	.asciz	"audio/mp4"
Ls_aac:	.asciz	"audio/aac"
Ls_hls:	.asciz	"application/vnd.apple.mpegurl"
Ls_range:	.asciz	"%lld-%lld"
Ls_200:	.asciz	"HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %lld\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
Ls_206:	.asciz	"HTTP/1.1 206 Partial Content\r\nContent-Type: %s\r\nContent-Length: %lld\r\nContent-Range: bytes %lld-%lld/%lld\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
Ls_404:	.asciz	"404 Not Found"
Ls_nothing:	.asciz	"Nothing playing"
Ls_dashes:	.asciz	"--:--"
	.popsection

; ---- Small utilities ----

; copt(option, value) — curl_easy_setopt on the handle in x19 (the variadic value goes on the stack).
	.p2align 2
copt:
	stp	x2, x30, [sp, #-16]!
	mov	x0, x19
	bl	_curl_easy_setopt
	ldp	x2, x30, [sp], #16
	ret

; curl_new() -> a libcurl handle in the shared pool: connections, TLS sessions and DNS answers carry over between requests and threads.
curl_new:
	FRAME	1
	bl	_curl_easy_init
	mov	x19, x0
	cbz	x0, Lret1
	ldr	x2, [x28, #G_SHARE]
	mov	w1, #CURLOPT_SHARE
	bl	copt
	mov	x0, x19
	b	Lret1

; shopt(option, value) — curl_share_setopt on the pool in x19 (the variadic value goes on the stack).
shopt:
	stp	x2, x30, [sp, #-16]!
	mov	x0, x19
	bl	_curl_share_setopt
	ldp	x2, x30, [sp], #16
	ret

; share_init() — the pool, with a lock per kind of shared data so any thread can use it.
share_init:
	FRAME	1
	bl	_curl_share_init
	mov	x19, x0
	str	x0, [x28, #G_SHARE]
	cbz	x0, Lret1
	adr	x2, share_lock
	mov	w1, #CURLSHOPT_LOCKFUNC
	bl	shopt
	adr	x2, share_unlock
	mov	w1, #CURLSHOPT_UNLOCKFUNC
	bl	shopt
	mov	x2, #CURL_LOCK_DATA_DNS
	mov	w1, #CURLSHOPT_SHARE
	bl	shopt
	mov	x2, #CURL_LOCK_DATA_SSL_SESSION
	mov	w1, #CURLSHOPT_SHARE
	bl	shopt
	mov	x2, #CURL_LOCK_DATA_CONNECT
	mov	w1, #CURLSHOPT_SHARE
	bl	shopt
	b	Lret1

; share_lock / share_unlock(handle, data) — the pool's lock for that kind of data.
	ENTRY	share_lock
	add	x0, x28, #G_SHLOCKS
	add	x0, x0, w1, uxtw #2
	b	_os_unfair_lock_lock
	ENTRY	share_unlock
	add	x0, x28, #G_SHLOCKS
	add	x0, x0, w1, uxtw #2
	b	_os_unfair_lock_unlock

; copt1(option) — set an option of the handle in x19 to 1.
copt1:
	mov	x2, #1
	b	copt

; status_of(handle) -> the HTTP status of its last response.
status_of:
	FRAME	0, 16
	str	xzr, [sp, #8]
	add	x9, sp, #8
	str	x9, [sp]
	mov	w1, #(CURLINFO_RESPONSE_CODE & 0xffff)
	movk	w1, #(CURLINFO_RESPONSE_CODE >> 16), lsl #16
	bl	_curl_easy_getinfo
	ldr	x0, [sp, #8]
	b	Lret0

; buf_cb(data, size, nmemb, buf) — append to a NUL-terminated buffer {data, len} of at most BUF_MAX bytes.
	ENTRY	buf_cb
	FRAME	2
	mul	x19, x1, x2
	mov	x20, x0
	mov	x21, x3
	ldp	x0, x22, [x21]
	add	x1, x22, x19
	mov	x9, #BUF_MAX
	cmp	x1, x9
	b.hi	Lbc_fail
	add	x1, x1, #1
	bl	_realloc
	cbz	x0, Lbc_fail
	add	x9, x22, x19
	stp	x0, x9, [x21]
	add	x0, x0, x22
	mov	x1, x20
	mov	x2, x19
	bl	_memcpy
	strb	wzr, [x0, x19]
	mov	x0, x19
	b	Lret2
Lbc_fail:
	mov	x0, #0
	b	Lret2

; send_all(fd, data, len) — write every byte; w0 = 1 on success.
send_all:
	FRAME	2
	mov	w19, w0
	mov	x20, x1
	mov	x21, x2
Lsa_loop:
	mov	w0, #1
	cbz	x21, Lret2
	mov	w0, w19
	mov	x1, x20
	mov	x2, x21
	bl	_write
	cmp	x0, #0
	b.gt	Lsa_adv
	mov	w0, #0
	b	Lret2
Lsa_adv:
	add	x20, x20, x0
	sub	x21, x21, x0
	b	Lsa_loop

; nextstr(p) -> the string after p in a packed list.
nextstr:
	FRAME	1
	mov	x19, x0
	bl	_strlen
	add	x0, x19, x0
	add	x0, x0, #1
	b	Lret1

; lock / unlock — take or release G's lock.
lock:
	add	x0, x28, #G_LOCK
	b	_os_unfair_lock_lock
unlock:
	add	x0, x28, #G_LOCK
	b	_os_unfair_lock_unlock

; post_main(work, context) — run work(context) on the main thread.
post_main:
	mov	x2, x0
	MAINQ	x0
	b	_dispatch_async_f

; ui_post_refresh() — re-render on the main thread.
ui_post_refresh:
	adr	x0, ui_refresh
	mov	x1, #0
	b	post_main

; ui_post_error(message) — show a static error message from any thread.
ui_post_error:
	mov	x1, x0
	adr	x0, ui_error_cb
	b	post_main

; ---- XML and time helpers ----

; xml_unescape(text) — decode XML entities in place.
xml_unescape:
	mov	x1, x0
	mov	x2, x0
Lxu_loop:
	ldrb	w3, [x1]
	cbz	w3, Lxu_done
	cmp	w3, #'&'
	b.ne	Lxu_copy
	GADDR	x4, Lxml_entities
Lxu_entity:
	ldrb	w5, [x4]
	cbz	w5, Lxu_copy              ; unknown entity: keep the '&'
	add	x6, x4, #1
	add	x7, x1, #1
Lxu_cmp:
	ldrb	w8, [x6], #1
	cbz	w8, Lxu_hit
	ldrb	w9, [x7], #1
	cmp	w8, w9
	b.eq	Lxu_cmp
	add	x4, x4, #8
	b	Lxu_entity
Lxu_hit:
	strb	w5, [x2], #1
	mov	x1, x7
	b	Lxu_loop
Lxu_copy:
	strb	w3, [x2], #1
	add	x1, x1, #1
	b	Lxu_loop
Lxu_done:
	strb	wzr, [x2]
	ret

; xml_escape(text) -> malloc'd copy with & < > " ' as entities, or NULL.
xml_escape:
	FRAME	1
	mov	x19, x0
	bl	_strlen
	mov	x9, #6
	madd	x0, x0, x9, x9            ; the longest entity is 6 bytes
	bl	_malloc
	cbz	x0, Lret1
	mov	x20, x0
	mov	x2, x0
	mov	x1, x19
Lxe_loop:
	ldrb	w3, [x1], #1
	cbz	w3, Lxe_end
	GADDR	x4, Lxml_entities
Lxe_find:
	ldrb	w5, [x4]
	cbz	w5, Lxe_plain
	cmp	w5, w3
	b.eq	Lxe_emit
	add	x4, x4, #8
	b	Lxe_find
Lxe_emit:
	mov	w6, #'&'
Lxe_name:
	strb	w6, [x2], #1
	ldrb	w6, [x4, #1]!
	cbnz	w6, Lxe_name
	b	Lxe_loop
Lxe_plain:
	strb	w3, [x2], #1
	b	Lxe_loop
Lxe_end:
	strb	wzr, [x2]
	mov	x0, x20
	b	Lret1

; xml_tag(xml, tag, out, cap) — copy and unescape the text of the first <tag>; w0 = 1 if found and it fits.
xml_tag:
	FRAME	3
	mov	x19, x0
	mov	x24, x0
	mov	x20, x1
	mov	x21, x2
	mov	x22, x3
	mov	x0, x1
	bl	_strlen
	mov	x23, x0
Lxt_find:
	mov	x0, x19
	mov	x1, x20
	bl	_strstr
	cbz	x0, Lxt_no
	add	x19, x0, #1
	cmp	x0, x24
	b.ls	Lxt_find
	ldurb	w9, [x0, #-1]
	cmp	w9, #'<'
	b.ne	Lxt_find
	add	x19, x0, x23
	ldrb	w9, [x19], #1
	cmp	w9, #'>'
	b.ne	Lxt_find
	mov	x0, x19
	mov	w1, #'<'
	bl	_strchr                   ; the text ends where the next tag starts
	cbz	x0, Lxt_no
	sub	x23, x0, x19
	cmp	x23, x22
	b.hs	Lxt_no
	mov	x0, x21
	mov	x1, x19
	add	x2, x23, #1
	bl	_strlcpy
	mov	x0, x21
	bl	xml_unescape
	mov	w0, #1
	b	Lret3
Lxt_no:
	mov	w0, #0
	b	Lret3

; hms(text) -> seconds of "h:mm:ss"; a fraction and anything after it are ignored.
hms:
	mov	x9, #0
	mov	x10, #0
	mov	x12, #60
	mov	x13, #10
Lhm_next:
	ldrb	w11, [x0], #1
	cmp	w11, #':'
	b.eq	Lhm_colon
	sub	w11, w11, #'0'
	cmp	w11, #9
	b.hi	Lhm_end
	madd	x10, x10, x13, x11
	b	Lhm_next
Lhm_colon:
	madd	x9, x9, x12, x10
	mov	x10, #0
	b	Lhm_next
Lhm_end:
	madd	x0, x9, x12, x10
	ret

; fmt_time(seconds, out[16], hours) — "m:ss", or "h:mm:ss" from one hour up or when hours is set.
fmt_time:
	FRAME	1, 32
	mov	x19, x1
	cmp	x0, #0
	csel	x0, x0, xzr, gt
	mov	x9, #3600
	udiv	x10, x0, x9
	msub	x11, x10, x9, x0
	mov	x9, #60
	udiv	x12, x11, x9
	msub	x13, x12, x9, x11
	orr	x14, x10, x2
	stp	x10, x12, [sp]
	str	x13, [sp, #16]
	CSTR	x2, "%ld:%02ld:%02ld"
	cbnz	x14, Lft_print
	stp	x12, x13, [sp]
	CSTR	x2, "%ld:%02ld"
Lft_print:
	mov	x0, x19
	mov	x1, #16
	bl	_snprintf
	b	Lret1

; tag_num(xml, tag) -> a tag's "h:mm:ss" in seconds, or its plain number; -1 when the response or the tag is missing.
tag_num:
	FRAME	0, 16
	cbz	x0, Ltn_none
	mov	x2, sp
	mov	x3, #16
	bl	xml_tag
	cbz	w0, Ltn_none
	mov	x0, sp
	bl	hms                       ; a number without colons comes back as it is
	b	Lret0
Ltn_none:
	mov	x0, #-1
	b	Lret0

; ---- HTTP (libcurl) and SOAP ----

; http(url, body, headers, buf, timeout_ms) — one request on the handle in x19 into buf {data, len}; w0 = 1 on success, buf empty otherwise.
http:
	FRAME	3
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	mov	x23, x3
	mov	x2, x4
	mov	w1, #CURLOPT_TIMEOUT_MS
	bl	copt
	mov	x2, x20
	mov	w1, #CURLOPT_URL
	bl	copt
	mov	w1, #CURLOPT_NOSIGNAL
	bl	copt1
	mov	w1, #CURLOPT_FOLLOWLOCATION
	bl	copt1
	mov	w1, #CURLOPT_FAILONERROR      ; error pages are not answers
	bl	copt1
	adr	x2, buf_cb
	mov	w1, #CURLOPT_WRITEFUNCTION
	bl	copt
	mov	x2, x23
	mov	w1, #CURLOPT_WRITEDATA
	bl	copt
	cbz	x21, Lht_go
	mov	x2, x21
	mov	w1, #CURLOPT_POSTFIELDS
	bl	copt
	mov	x2, x22
	mov	w1, #CURLOPT_HTTPHEADER
	bl	copt
Lht_go:
	stp	xzr, xzr, [x23]
	mov	x0, x19
	bl	_curl_easy_perform
	mov	w20, w0
	cbz	w0, Lht_ret
	ldr	x0, [x23]
	bl	_free
	stp	xzr, xzr, [x23]
Lht_ret:
	cmp	w20, #0
	cset	w0, eq
	b	Lret3

; dev_http(url, body, headers, timeout_ms) — a request through the LAN on the device queue's keep-alive handle; body or NULL.
dev_http:
	FRAME	3, 16
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	mov	x23, x3
	ldr	x19, [x28, #G_CURL]
	mov	x0, x19
	bl	_curl_easy_reset
	BADDR	x2, B_LANIP               ; set: only discovered devices are asked
	mov	w1, #CURLOPT_INTERFACE        ; leave through the LAN even with a VPN up
	bl	copt
	mov	x2, #CONNECT_TIMEOUT_MS
	mov	w1, #CURLOPT_CONNECTTIMEOUT_MS
	bl	copt
	mov	x0, x20
	mov	x1, x21
	mov	x2, x22
	mov	x3, sp
	mov	x4, x23
	bl	http
	ldr	x0, [sp]
	b	Lret3

; av / rc (action, args) — upnp on the device's AVTransport / RenderingControl service.
av:
	GADDR	x2, Ls_avt
	b	upnp
rc:
	GADDR	x2, Ls_rc

; upnp(action, args, service) — a SOAP call on the selected device; the response, or NULL on error or fault.
upnp:
	FRAME	4, 48
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	stp	x22, x20, [sp]
	add	x0, sp, #32
	CSTR	x1, "SOAPACTION: \"urn:schemas-upnp-org:service:%s:1#%s\""
	bl	_asprintf
	stp	x20, x22, [sp]
	stp	x21, x20, [sp, #16]
	add	x0, sp, #40
	CSTR	x1, "<?xml version=\"1.0\" encoding=\"utf-8\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:%s xmlns:u=\"urn:schemas-upnp-org:service:%s:1\"><InstanceID>0</InstanceID>%s</u:%s></s:Body></s:Envelope>"
	bl	_asprintf
	mov	x23, #0
	ldp	x24, x25, [sp, #32]
	cbz	x24, Lup_free
	cbz	x25, Lup_free
	mov	x0, #0
	CSTR	x1, "Content-Type: text/xml; charset=\"utf-8\""
	bl	_curl_slist_append
	mov	x1, x24
	bl	_curl_slist_append
	mov	x26, x0
	ldrb	w9, [x22]
	cmp	w9, #'A'
	cset	w9, ne
	mov	x10, #DEV_AVT
	lsl	x10, x10, x9              ; DEV_AVT, or DEV_RC for RenderingControl
	BADDR	x0, B_CUR
	add	x0, x0, x10
	mov	x1, x25
	mov	x2, x26
	mov	x3, #SOAP_TIMEOUT_MS
	bl	dev_http
	mov	x23, x0
	mov	x0, x26
	bl	_curl_slist_free_all
	cbz	x23, Lup_free
	mov	x0, x23
	CSTR	x1, "Response"
	bl	_strstr
	cbnz	x0, Lup_free
	mov	x0, x23                   ; a fault
	bl	_free
	mov	x23, #0
Lup_free:
	mov	x0, x24
	bl	_free
	mov	x0, x25
	bl	_free
	mov	x0, x23
	b	Lret4

; avcmd / rccmd (action, args) — a command to the device; w0 = 1 if it accepted it.
avcmd:
	GADDR	x2, Ls_avt
	b	Lcmd
rccmd:
	GADDR	x2, Ls_rc
Lcmd:
	FRAME	0
	bl	upnp
	cbz	x0, Lret0
	bl	_free
	mov	w0, #1
	b	Lret0

; ---- Discovery (a worker, then the device queue) ----

; discover_lan() — our private IPv4 address and mask into G_LAN: en0's, else the first one; w0 = 1 if found.
discover_lan:
	FRAME	3, 16
	mov	x0, sp
	bl	_getifaddrs
	mov	x21, #0                   ; the chosen interface
	cbnz	w0, Ldl_ret
	ldr	x19, [sp]
Ldl_loop:
	cbz	x19, Ldl_take
	ldr	x9, [x19, #IFA_ADDR]
	cbz	x9, Ldl_next
	ldrb	w10, [x9, #1]
	cmp	w10, #AF_INET
	b.ne	Ldl_next
	ldr	x10, [x19, #IFA_NETMASK]
	cbz	x10, Ldl_next
	ldr	w10, [x19, #IFA_FLAGS]
	tbz	w10, #0, Ldl_next         ; IFF_UP
	tbnz	w10, #3, Ldl_next         ; IFF_LOOPBACK
	ldr	w10, [x9, #4]
	rev	w20, w10                  ; address in host order
	lsr	w10, w20, #24
	cmp	w10, #10                  ; 10.0.0.0/8
	b.eq	Ldl_private
	lsr	w10, w20, #20
	cmp	w10, #0xac1               ; 172.16.0.0/12
	b.eq	Ldl_private
	lsr	w10, w20, #16
	mov	w11, #0xc0a8              ; 192.168.0.0/16
	cmp	w10, w11
	b.ne	Ldl_next
Ldl_private:
	cbnz	x21, Ldl_en0
	mov	x21, x19                  ; the first one, unless en0 comes later
Ldl_en0:
	ldr	x0, [x19, #IFA_NAME]
	CSTR	x1, "en0"
	bl	_strcmp
	cbnz	w0, Ldl_next
	mov	x21, x19
	b	Ldl_take
Ldl_next:
	ldr	x19, [x19]
	b	Ldl_loop
Ldl_take:
	cbz	x21, Ldl_free
	ldr	x9, [x21, #IFA_ADDR]
	ldr	w20, [x9, #4]
	ldr	x10, [x21, #IFA_NETMASK]
	ldr	w10, [x10, #4]
	orr	x10, x20, x10, lsl #32
	str	x10, [x28, #G_LAN]        ; one store: readers see a matching pair
Ldl_free:
	ldr	x0, [sp]
	bl	_freeifaddrs
Ldl_ret:
	cmp	x21, #0
	cset	w0, ne
	b	Lret3

; control_url(xml, service, base, out[256]) — the absolute control URL of a service; w0 = 1 if found.
control_url:
	FRAME	3, 32
	mov	x19, x2
	mov	x20, x3
	bl	_strstr
	cbz	x0, Lcl_no
	CSTR	x1, "<controlURL>"
	bl	_strstr
	cbz	x0, Lcl_no
	add	x21, x0, #12
	mov	x0, x21
	mov	w1, #'<'
	bl	_strchr
	cbz	x0, Lcl_no
	sub	x22, x0, x21
	cmp	x22, #200
	b.hs	Lcl_no
	mov	x0, x21
	CSTR	x1, "http"
	mov	x2, #4
	bl	_strncmp
	GADDR	x9, Ls_slash+1
	mov	x10, x9
	cbz	w0, Lcl_print             ; absolute already
	mov	x9, x19
	ldrb	w11, [x21]
	cmp	w11, #'/'
	b.eq	Lcl_print                 ; relative to the host
	GADDR	x10, Ls_slash
Lcl_print:
	stp	x9, x10, [sp]
	stp	x22, x21, [sp, #16]
	mov	x0, x20
	mov	x1, #256
	CSTR	x2, "%s%s%.*s"
	bl	_snprintf
	mov	w0, #1
	b	Lret3
Lcl_no:
	mov	w0, #0
	b	Lret3

; describe(location, dev) — fill a device entry from its UPnP description; w0 = 1 if it plays media.
describe:
	FRAME	3, 400                    ; +144: the ConnectionManager's control URL
	mov	x19, x0
	mov	x20, x1
	mov	x1, #0
	mov	x2, #0
	mov	x3, #DESC_TIMEOUT_MS
	bl	dev_http
	mov	x21, x0
	mov	w22, #0
	cbz	x21, Lde_ret
	mov	x0, x19                   ; base = scheme://host:port of the description
	GADDR	x1, Ls_sep
	bl	_strstr
	cbz	x0, Lde_free
	add	x23, x0, #3
	mov	x0, x23
	GADDR	x1, Ls_slash
	bl	_strcspn
	add	x9, x23, x0
	sub	x2, x9, x19
	cmp	x2, #128
	b.hs	Lde_free
	add	x0, x20, #DEV_BASE
	mov	x1, x19
	add	x2, x2, #1
	bl	_strlcpy
	mov	x0, x21
	CSTR	x1, "urn:schemas-upnp-org:service:AVTransport:1"
	add	x2, x20, #DEV_BASE
	add	x3, x20, #DEV_AVT
	bl	control_url
	cbz	w0, Lde_free              ; it cannot play media
	strb	wzr, [x20, #DEV_RC]       ; none unless it has one
	mov	x0, x21
	CSTR	x1, "urn:schemas-upnp-org:service:RenderingControl:1"
	add	x2, x20, #DEV_BASE
	add	x3, x20, #DEV_RC
	bl	control_url
	strb	wzr, [x20, #DEV_VIDEO]    ; a TV if its sink takes video
	mov	x0, x21
	CSTR	x1, "urn:schemas-upnp-org:service:ConnectionManager:1"
	add	x2, x20, #DEV_BASE
	add	x3, sp, #144
	bl	control_url
	cbz	w0, Lde_named
	add	x0, sp, #144
	bl	sink_video
	strb	w0, [x20, #DEV_VIDEO]
Lde_named:
	mov	x0, x21                   ; "Room · Model" (Sonos), else friendlyName
	CSTR	x1, "roomName"
	add	x2, sp, #16
	mov	x3, #64
	bl	xml_tag
	mov	w22, w0
	mov	x0, x21
	CSTR	x1, "modelName"
	add	x2, sp, #80
	mov	x3, #64
	bl	xml_tag
	cbz	w22, Lde_friendly
	add	x1, sp, #16
	cbz	w0, Lde_room
	add	x10, sp, #80
	stp	x1, x10, [sp]
	add	x0, x20, #DEV_NAME
	mov	x1, #128
	CSTR	x2, "%s \302\267 %s"
	bl	_snprintf
	b	Lde_yes
Lde_friendly:
	mov	x0, x21
	CSTR	x1, "friendlyName"
	add	x2, x20, #DEV_NAME
	mov	x3, #128
	bl	xml_tag
	cbnz	w0, Lde_yes
	add	x1, x20, #DEV_BASE        ; unnamed: its address
Lde_room:
	add	x0, x20, #DEV_NAME
	mov	x2, #128
	bl	_strlcpy
Lde_yes:
	mov	w22, #1
Lde_free:
	mov	x0, x21
	bl	_free
Lde_ret:
	mov	w0, w22
	b	Lret3

; sink_video(control) -> what the renderer's ConnectionManager says it can play beyond sound: 1 = video, 2 = HLS, or both.
sink_video:
	FRAME	2
	mov	x19, x0
	mov	x0, #0
	CSTR	x1, "Content-Type: text/xml; charset=\"utf-8\""
	bl	_curl_slist_append
	CSTR	x1, "SOAPACTION: \"urn:schemas-upnp-org:service:ConnectionManager:1#GetProtocolInfo\""
	bl	_curl_slist_append
	mov	x20, x0
	mov	x0, x19
	CSTR	x1, "<?xml version=\"1.0\" encoding=\"utf-8\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:GetProtocolInfo xmlns:u=\"urn:schemas-upnp-org:service:ConnectionManager:1\"/></s:Body></s:Envelope>"
	mov	x2, x20
	mov	x3, #DESC_TIMEOUT_MS
	bl	dev_http
	mov	x21, x0
	mov	x0, x20
	bl	_curl_slist_free_all
	mov	w22, #0
	cbz	x21, Lsv_answer
	mov	x0, x21
	CSTR	x1, ":video/"
	bl	_strcasestr
	cmp	x0, #0
	cset	w22, ne
	mov	x0, x21
	CSTR	x1, "mpegurl"
	bl	_strcasestr
	cmp	x0, #0
	cset	w9, ne
	orr	w22, w22, w9, lsl #1
	mov	x0, x21
	bl	_free
Lsv_answer:
	mov	w0, w22
	b	Lret2

; header_value(text, pattern, out[256]) — copy the value of the header that pattern ("\nName:") finds; NULL if absent.
header_value:
	FRAME	2
	mov	x19, x1
	mov	x20, x2
	bl	_strcasestr
	cbz	x0, Lret2
	mov	x21, x0
	mov	x0, x19
	bl	_strlen
	add	x21, x21, x0
Lhv_space:
	ldrb	w9, [x21]
	cmp	w9, #' '
	b.ne	Lhv_value
	add	x21, x21, #1
	b	Lhv_space
Lhv_value:
	mov	x0, x21
	GADDR	x1, Ls_crlf
	bl	_strcspn
	mov	x9, #255
	cmp	x0, x9
	csel	x2, x0, x9, lo            ; truncated to fit
	add	x2, x2, #1
	mov	x0, x20
	mov	x1, x21
	bl	_strlcpy
	mov	x0, x20
	b	Lret2

; ssdp_collect(scan) — the description URLs of the media renderers that answer an M-SEARCH from the LAN address, each once.
	.pushsection __DATA,__data
Lmsearch:	.ascii	"M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
Lmsearch_end:
	.popsection
ssdp_collect:
	FRAME	4, 1616
	; +16 local address, +32 destination, +48 timeval, +80 datagram
	mov	x19, x0
	add	x24, x0, #SC_LOCS
	mov	x23, #0
	mov	w0, #AF_INET
	mov	w1, #SOCK_DGRAM
	mov	w2, #0
	bl	_socket
	tbnz	w0, #31, Lret4
	mov	w20, w0
	mov	w9, #SOCKADDR_IN_HEAD
	ldr	w10, [x28, #G_LAN]        ; the LAN address, port 0
	stp	w9, w10, [sp, #16]
	str	xzr, [sp, #24]
	mov	w0, w20
	add	x1, sp, #16
	mov	w2, #16
	bl	_bind                     ; replies come back to the LAN address
	cbnz	w0, Lsc_close
	mov	w0, w20
	mov	w1, #IPPROTO_IP
	mov	w2, #IP_MULTICAST_IF
	add	x3, sp, #20
	mov	w4, #4
	bl	_setsockopt               ; and the search leaves through it, even with a VPN up
	mov	x9, #((SSDP_WAIT_MS * 1000) & 0xffff)
	movk	x9, #((SSDP_WAIT_MS * 1000) >> 16), lsl #16
	stp	xzr, x9, [sp, #48]        ; struct timeval: the silence that ends an attempt
	mov	w0, w20
	mov	w1, #SOL_SOCKET
	mov	w2, #SO_RCVTIMEO
	add	x3, sp, #48
	mov	w4, #16
	bl	_setsockopt
	mov	w9, #SOCKADDR_IN_HEAD
	movk	w9, #SSDP_PORT_BE, lsl #16
	mov	w10, #0xffef              ; 239.255.255.250
	movk	w10, #0xfaff, lsl #16
	stp	w9, w10, [sp, #32]
	str	xzr, [sp, #40]
	mov	w21, #SSDP_ROUNDS
Lsc_round:
	mov	w0, w20
	GADDR	x1, Lmsearch
	mov	x2, #(Lmsearch_end - Lmsearch)
	mov	w3, #0
	add	x4, sp, #32
	mov	w5, #16
	bl	_sendto
	mov	w22, #SSDP_MAX_REPLIES
Lsc_wait:
	mov	w0, w20
	add	x1, sp, #80
	mov	x2, #1535
	mov	w3, #0
	bl	_recv
	cmp	x0, #0
	b.le	Lsc_next                  ; quiet for a while: next attempt
	add	x9, sp, #80
	strb	wzr, [x9, x0]
	add	x0, sp, #80
	CSTR	x1, "\nLOCATION:"
	add	x2, x24, x23, lsl #8      ; into the next free slot
	bl	header_value
	cbz	x0, Lsc_counted
	mov	x25, #0
Lsc_dup:
	cmp	x25, x23
	b.hs	Lsc_new
	add	x0, x24, x25, lsl #8
	add	x1, x24, x23, lsl #8
	bl	_strcmp
	add	x25, x25, #1
	cbnz	w0, Lsc_dup
	b	Lsc_counted               ; heard already
Lsc_new:
	add	x23, x23, #1
	str	w23, [x19, #SC_COUNT]
	cmp	x23, #(MAX_DEVS - 1)
	b.hs	Lsc_close                 ; full
Lsc_counted:
	subs	w22, w22, #1
	b.ne	Lsc_wait
Lsc_next:
	subs	w21, w21, #1
	b.ne	Lsc_round
Lsc_close:
	mov	w0, w20
	bl	_close
	b	Lret4

; scan_job(mode) — the slow half of a search, on a worker so device commands never wait for it: our LAN, then who answers.
	ENTRY	scan_job
	FRAME	2, 16
	BADDR	x20, B_SCAN
	mov	x9, #SC_SIZE
	madd	x20, x0, x9, x20          ; this kind's handoff
	stp	w0, wzr, [x20, #SC_MODE]
	bl	discover_lan
	cbz	w0, Lsj_queue             ; no LAN: This Mac only
	CSTR	x0, "BEAM_HOST"
	bl	_getenv
	mov	x21, x0
	cbz	x0, Lsj_ssdp
	ldrb	w9, [x0]
	cbz	w9, Lsj_ssdp
	GADDR	x1, Ls_sep
	bl	_strstr
	cmp	x0, #0
	CSTR	x2, "http://%s:1400/xml/device_description.xml"
	CSTR	x9, "%s"
	csel	x2, x9, x2, ne            ; a description URL, or a host with Sonos' default one
	str	x21, [sp]
	add	x0, x20, #SC_LOCS
	mov	x1, #256
	bl	_snprintf
	mov	w9, #1
	str	w9, [x20, #SC_COUNT]
	b	Lsj_queue
Lsj_ssdp:
	mov	x0, x20
	bl	ssdp_collect
Lsj_queue:
	ldr	x0, [x28, #G_QUEUE]
	mov	x1, x20
	adr	x2, discover_job
	bl	_dispatch_async_f
	b	Lret2

; discover_job(scan) — the device queue's half: describe the new renderers, publish the list, keep or pick the selection.
	ENTRY	discover_job
	FRAME	4, 272 + MAX_DEVS * DEV_SIZE
	mov	x24, x0
	ldr	w26, [x24, #SC_MODE]
	ldr	w9, [x28, #G_LAN]         ; our requests leave through the LAN address
	str	w9, [sp]
	mov	w0, #AF_INET
	mov	x1, sp
	BADDR	x2, B_LANIP
	mov	w3, #16
	bl	_inet_ntop
	add	x19, sp, #272
	LOCK
	mov	w20, #1                   ; This Mac
	mov	x2, #DEV_SIZE
	cbz	w26, Ldj_copy
	ldr	w20, [x28, #G_DEVN]       ; the picker opened: what is listed stays, in place
	mov	x2, #(MAX_DEVS * DEV_SIZE)
Ldj_copy:
	mov	x0, x19
	BADDR	x1, B_DEVS
	bl	_memcpy
	UNLOCK
	mov	x21, #0
Ldj_loc:
	ldr	w9, [x24, #SC_COUNT]
	cmp	x21, x9
	b.hs	Ldj_pick
	add	x22, x24, #SC_LOCS
	add	x22, x22, x21, lsl #8
	add	x21, x21, #1
	mov	x23, #1                   ; skip devices already listed
Ldj_dup:
	cmp	x23, x20
	b.hs	Ldj_new
	mov	x9, #DEV_SIZE
	madd	x25, x23, x9, x19
	add	x25, x25, #DEV_BASE
	mov	x0, x25
	bl	_strlen
	mov	x2, x0
	mov	x0, x22
	mov	x1, x25
	bl	_strncmp
	add	x23, x23, #1
	cbnz	w0, Ldj_dup
	b	Ldj_loc
Ldj_new:
	cmp	x20, #MAX_DEVS
	b.hs	Ldj_pick                  ; the list is full
	mov	x9, #DEV_SIZE
	madd	x1, x20, x9, x19
	mov	x0, x22
	bl	describe
	add	x20, x20, w0, uxtw
	b	Ldj_loc
Ldj_pick:
	mov	w21, #-1                  ; the selection stays
	cbnz	w26, Ldj_store
	mov	w21, #0
	BADDR	x22, B_CUR
	ldrb	w9, [x22, #DEV_BASE]
	cbz	w9, Ldj_auto              ; This Mac is selected
	mov	x23, #1                   ; keep the selected device if it is still there
Ldj_find:
	cmp	x23, x20
	b.hs	Ldj_store
	mov	x9, #DEV_SIZE
	madd	x0, x23, x9, x19
	add	x0, x0, #DEV_BASE
	add	x1, x22, #DEV_BASE
	bl	_strcmp
	add	x23, x23, #1
	cbnz	w0, Ldj_find
	sub	w21, w23, #1
	b	Ldj_store
Ldj_auto:
	ldr	w9, [x28, #G_CHOSE]
	cbnz	w9, Ldj_store             ; This Mac was picked by hand
	cmp	x20, #1
	csinc	w21, wzr, wzr, ls         ; otherwise the first device found
Ldj_store:
	LOCK
	BADDR	x0, B_DEVS
	mov	x1, x19
	mov	x2, #(MAX_DEVS * DEV_SIZE)
	bl	_memcpy
	str	w20, [x28, #G_DEVN]
	BADDR	x9, B_NOW
	ldr	w10, [x9, #NOW_DEVREV]
	add	w10, w10, #1
	str	w10, [x9, #NOW_DEVREV]
	UNLOCK
	mov	w9, #1                    ; a search of this kind may start again
	lsl	w9, w9, w26
	add	x10, x28, #G_DISC
	stclrl	w9, [x10]
	tbnz	w21, #31, Ldj_kept
	mov	w0, w21
	bl	select_apply
	b	Lret4
Ldj_kept:
	bl	ui_post_refresh
	b	Lret4

; select_apply(index) — make device index current, publish it and poll it.
select_apply:
	FRAME	2
	mov	w19, w0
	LOCK
	ldr	w9, [x28, #G_DEVN]
	cmp	w19, w9
	csel	w19, w19, wzr, lo         ; gone: back to This Mac
	BADDR	x20, B_DEVS
	mov	x9, #DEV_SIZE
	madd	x20, x19, x9, x20
	BADDR	x0, B_CUR
	mov	x1, x20
	mov	x2, #DEV_SIZE
	bl	_memcpy
	BADDR	x21, B_NOW
	str	w19, [x21, #NOW_SEL]
	add	x0, x21, #NOW_NAME
	add	x1, x20, #DEV_NAME
	mov	x2, #128
	bl	_strlcpy
	str	wzr, [x21, #NOW_STATE]    ; unknown until polled
	ldrb	w9, [x20, #DEV_VIDEO]
	str	w9, [x28, #G_TV]          ; a TV gets H.264, which every TV decodes
	stp	xzr, xzr, [x21, #NOW_POS]
	strb	wzr, [x21, #NOW_TITLE]
	strb	wzr, [x21, #NOW_ARTIST]
	strb	wzr, [x21, #NOW_ART]
	UNLOCK
	bl	poll_now
	b	Lret2

; select_job — a device picked by hand.
	ENTRY	select_job
	mov	w9, #1
	str	w9, [x28, #G_CHOSE]
	b	select_apply

; ---- State polling (device queue) ----

; poll_job — the timer's poll; one is queued at most.
	ENTRY	poll_job
	FRAME	0
	bl	poll_now
	add	x9, x28, #G_POLLB
	stlr	wzr, [x9]
	b	Lret0

; poll_now() — read state, position, track, volume and mute from the device, publish them; re-render.
	.equ P_RESP,	16                ; 4 responses: transport, position, volume, mute
	.equ P_STATE,	48                ; char[32]
	.equ P_URI,	80                ; char[2048]: track URI, then artwork URI
	.equ P_NOW,	P_URI + 2048      ; new snapshot
	.equ P_META,	P_NOW + NOW_SIZE  ; char[8192]: DIDL-Lite
	.equ P_SIZE,	P_META + 8192
poll_now:
	FRAME	3, P_SIZE
	BADDR	x9, B_CUR
	ldrb	w9, [x9, #DEV_AVT]
	cbz	w9, Lpn_render            ; This Mac fills the snapshot itself
	BADDR	x19, B_NOW
	add	x20, sp, #P_NOW
	LOCK
	mov	x0, x20
	mov	x1, x19
	mov	x2, #NOW_SIZE
	bl	_memcpy
	UNLOCK
	stp	xzr, xzr, [sp, #P_RESP]
	stp	xzr, xzr, [sp, #P_RESP + 16]
	str	wzr, [x20, #NOW_STATE]    ; offline unless it answers
	CSTR	x0, "GetTransportInfo"
	GADDR	x1, Ls_slash+1
	bl	av
	str	x0, [sp, #P_RESP]
	cbz	x0, Lpn_publish           ; unreachable: skip the other requests
	CSTR	x1, "CurrentTransportState"
	add	x2, sp, #P_STATE
	strb	wzr, [x2]
	mov	x3, #32
	bl	xml_tag
	ldrb	w9, [sp, #P_STATE]        ; PLAYING, PAUSED_PLAYBACK, TRANSITIONING, else stopped
	ldrb	w10, [sp, #P_STATE + 1]
	mov	w11, #ST_STOPPED
	mov	w12, #ST_TRANSITIONING
	cmp	w9, #'T'
	csel	w11, w12, w11, eq
	cmp	w9, #'P'
	b.ne	Lpn_state
	mov	w11, #ST_PLAYING
	mov	w12, #ST_PAUSED
	cmp	w10, #'L'
	csel	w11, w11, w12, eq
Lpn_state:
	str	w11, [x20, #NOW_STATE]
	CSTR	x0, "GetPositionInfo"
	GADDR	x1, Ls_slash+1
	bl	av
	str	x0, [sp, #P_RESP + 8]
	CSTR	x0, "GetVolume"
	GADDR	x1, Ls_master
	bl	rc
	str	x0, [sp, #P_RESP + 16]
	CSTR	x0, "GetMute"
	GADDR	x1, Ls_master
	bl	rc
	str	x0, [sp, #P_RESP + 24]
	ldr	x21, [sp, #P_RESP + 8]
	cbz	x21, Lpn_volume
	stp	xzr, xzr, [x20, #NOW_POS] ; the position answer replaces the track
	strb	wzr, [x20, #NOW_TITLE]
	strb	wzr, [x20, #NOW_ARTIST]
	strb	wzr, [x20, #NOW_ART]
	mov	x0, x21
	CSTR	x1, "RelTime"
	bl	tag_num
	tbnz	x0, #63, Lpn_dur
	str	x0, [x20, #NOW_POS]
Lpn_dur:
	mov	x0, x21
	CSTR	x1, "TrackDuration"
	bl	tag_num
	tbnz	x0, #63, Lpn_uri
	str	x0, [x20, #NOW_DUR]
Lpn_uri:
	add	x22, sp, #P_URI
	strb	wzr, [x22]
	mov	x0, x21
	CSTR	x1, "TrackURI"
	mov	x2, x22
	mov	x3, #2048
	bl	xml_tag
	ldrb	w9, [x22]
	cbz	w9, Lpn_meta
	mov	x0, x22
	BADDR	x1, B_MYURI
	bl	_strcmp
	cbnz	w0, Lpn_meta
	add	x0, x20, #NOW_TITLE       ; our own stream: our metadata
	BADDR	x1, B_MYTRACK
	mov	x2, #T_SIZE
	bl	_memcpy
	ldr	x9, [x20, #NOW_DUR]
	cbnz	x9, Lpn_volume
	ldr	x9, [x28, #G_MYDUR]       ; the device does not know it yet
	str	x9, [x20, #NOW_DUR]
	b	Lpn_volume
Lpn_meta:
	mov	x0, x22                   ; one of our streams from an earlier session?
	GADDR	x1, Ls_stream
	bl	_strstr
	cbz	x0, Lpn_didl
	mov	x0, x22
	BADDR	x1, B_LANIP
	bl	_strstr
	cbz	x0, Lpn_didl
	stp	xzr, xzr, [x20, #NOW_POS] ; its proxy is gone: nothing is playing
	b	Lpn_volume
Lpn_didl:
	add	x23, x20, #NOW_SIZE       ; P_META
	mov	x0, x21
	CSTR	x1, "TrackMetaData"
	mov	x2, x23
	mov	x3, #8192
	bl	xml_tag                   ; first unescape: DIDL-Lite markup
	cbz	w0, Lpn_volume
	mov	x0, x23
	CSTR	x1, "dc:title"
	add	x2, x20, #NOW_TITLE
	mov	x3, #512
	bl	xml_tag                   ; second unescape: the text itself
	mov	x0, x23
	CSTR	x1, "dc:creator"
	add	x2, x20, #NOW_ARTIST
	mov	x3, #256
	bl	xml_tag
	mov	x0, x23
	CSTR	x1, "upnp:albumArtURI"
	mov	x2, x22
	mov	x3, #2048
	bl	xml_tag
	cbz	w0, Lpn_volume
	BADDR	x9, B_CUR
	add	x9, x9, #DEV_BASE
	GADDR	x10, Ls_slash+1
	ldrb	w11, [x22]
	cmp	w11, #'/'
	csel	x9, x9, x10, eq           ; relative: served by the device itself
	stp	x9, x22, [sp]
	add	x0, x20, #NOW_ART
	mov	x1, #2048
	CSTR	x2, "%s%s"
	bl	_snprintf
Lpn_volume:
	ldr	x0, [sp, #P_RESP + 16]
	CSTR	x1, "CurrentVolume"
	bl	tag_num
	tbnz	w0, #31, Lpn_mute
	str	w0, [x20, #NOW_VOL]
Lpn_mute:
	ldr	x0, [sp, #P_RESP + 24]
	CSTR	x1, "CurrentMute"
	bl	tag_num
	tbnz	w0, #31, Lpn_publish
	cmp	w0, #0
	cset	w0, ne
	str	w0, [x20, #NOW_MUTE]
Lpn_publish:
	LOCK
	mov	x0, x19
	mov	x1, x20
	mov	x2, #NOW_SIZE
	bl	_memcpy
	UNLOCK
	mov	x21, #P_RESP
Lpn_free:
	ldr	x0, [sp, x21]
	bl	_free
	add	x21, x21, #8
	cmp	x21, #(P_RESP + 32)
	b.lo	Lpn_free
Lpn_render:
	bl	ui_post_refresh
	b	Lret3

; ---- Transport and volume commands (device queue) ----

; report(ok) — tell the user when the device refused a command.
report:
	cbnz	w0, Lrp_ret
	CSTR	x0, "The device rejected the command."
	b	ui_post_error
Lrp_ret:
	ret

; av_done(action, args) — an AVTransport command; report a refusal, then poll right away.
av_done:
	FRAME	0
	bl	avcmd
	bl	report
	bl	poll_now
	b	Lret0

; toggle_job — pause when playing, play otherwise.
	ENTRY	toggle_job
	BADDR	x9, B_NOW
	ldr	w9, [x9, #NOW_STATE]
	GADDR	x0, Ls_play
	GADDR	x1, Ls_speed
	cmp	w9, #ST_PLAYING
	ccmp	w9, #ST_TRANSITIONING, #4, ne
	b.ne	av_done
	CSTR	x0, "Pause"
	GADDR	x1, Ls_slash+1
	b	av_done

; stop_job
	ENTRY	stop_job
	CSTR	x0, "Stop"
	GADDR	x1, Ls_slash+1
	b	av_done

; mute_job — toggle the device's own mute (the volume is kept).
	ENTRY	mute_job
	FRAME	0, 80
	BADDR	x9, B_NOW
	ldr	w9, [x9, #NOW_MUTE]
	eor	w9, w9, #1
	str	x9, [sp]
	add	x0, sp, #16
	mov	x1, #64
	CSTR	x2, "<Channel>Master</Channel><DesiredMute>%d</DesiredMute>"
	bl	_snprintf
	GADDR	x0, Ls_setmute
	add	x1, sp, #16
	bl	rccmd
	bl	report
	bl	poll_now
	b	Lret0

; set_volume(level) — set the volume and unmute; w0 = 1 on success.
set_volume:
	FRAME	1, 96
	mov	w19, w0
	BADDR	x20, B_NOW
	ldr	w9, [x20, #NOW_VOL]
	mov	w0, #1
	cmp	w9, w19
	b.eq	Lret1                     ; already there
	str	x19, [sp]
	add	x0, sp, #16
	mov	x1, #80
	CSTR	x2, "<Channel>Master</Channel><DesiredVolume>%d</DesiredVolume>"
	bl	_snprintf
	CSTR	x0, "SetVolume"
	add	x1, sp, #16
	bl	rccmd
	cbz	w0, Lret1
	LOCK
	str	w19, [x20, #NOW_VOL]
	UNLOCK
	ldr	w9, [x20, #NOW_MUTE]
	cbz	w9, Lsv_done
	GADDR	x0, Ls_setmute
	CSTR	x1, "<Channel>Master</Channel><DesiredMute>0</DesiredMute>"
	bl	rccmd
	cbz	w0, Lsv_done
	LOCK
	str	wzr, [x20, #NOW_MUTE]
	UNLOCK
Lsv_done:
	bl	ui_post_refresh
	mov	w0, #1
	b	Lret1

; vol_set(level) — set_volume within 0..100, reporting a refusal.
vol_set:
	FRAME	0
	bl	clamp100
	bl	set_volume
	bl	report
	b	Lret0

; vol_job — send the latest slider value.
	ENTRY	vol_job
	add	x9, x28, #G_VOLB
	stlr	wzr, [x9]
	add	x9, x28, #G_PVOL
	ldar	w0, [x9]
	b	vol_set

; volstep_job(delta) — change the volume by delta, within 0..100.
	ENTRY	volstep_job
	BADDR	x9, B_NOW
	ldr	w9, [x9, #NOW_VOL]
	add	w0, w9, w0
	b	vol_set

; clamp100(n) -> n within 0..100.
clamp100:
	cmp	w0, #0
	csel	w0, w0, wzr, gt
	mov	w9, #100
	cmp	w0, w9
	csel	w0, w0, w9, lt
	ret

; seek_job(seconds) — absolute seek.
	ENTRY	seek_job
	FRAME	0, 112
	add	x1, sp, #16
	mov	x2, #1
	bl	fmt_time
	add	x9, sp, #16
	str	x9, [sp]
	add	x0, sp, #32
	mov	x1, #80
	CSTR	x2, "<Unit>REL_TIME</Unit><Target>%s</Target>"
	bl	_snprintf
	CSTR	x0, "Seek"
	add	x1, sp, #32
	bl	avcmd
	cbnz	w0, Lsk_poll
	CSTR	x0, "Seeking is not available for this audio."
	bl	ui_post_error
Lsk_poll:
	bl	poll_now
	b	Lret0

; ---- Playing a link: main -> worker -> device queue -> main ----

; play_resolve(job) — resolve the link, hand it to the device or prepare This Mac's item, report to main.
	ENTRY	play_resolve
	FRAME	2
	mov	x19, x0
	bl	_objc_autoreleasePoolPush
	mov	x21, x0
	mov	x0, x19
	bl	resolve
	str	w0, [x19, #JOB_RESULT]
	cbnz	w0, Lpr_done
	LOCK
	BADDR	x9, B_NOW
	ldr	w20, [x9, #NOW_SEL]
	UNLOCK
	cbnz	w20, Lpr_device
	mov	x0, x19
	bl	local_prepare
	b	Lpr_done
Lpr_device:
	ldr	x0, [x28, #G_QUEUE]
	mov	x1, x19
	adr	x2, play_upnp
	bl	_dispatch_sync_f          ; keeps the job alive until the device answers
Lpr_done:
	mov	x0, x21
	bl	_objc_autoreleasePoolPop
	adr	x0, ui_play_done
	mov	x1, x19
	bl	post_main
	b	Lret2

; local_prepare(job) — This Mac's item: YouTube through the proxy at loopback (full-speed reads), its picture as HLS; anything else as it is.
local_prepare:
	FRAME	2
	mov	x20, x0
	ldr	w9, [x20, #JOB_KIND]
	add	x0, x20, #JOB_URL
	cbnz	w9, Llp_item
	ldr	w1, [x20, #JOB_LIVE]
	CSTR	x2, "127.0.0.1"
	ADDO	x3, x20, JOB_LOCAL
	bl	slot_uri
	ADDO	x9, x20, JOB_VURL
	ldrb	w9, [x9]
	cbz	w9, Llp_hls
	ldr	w10, [x20, #JOB_LIVE]
	cbz	w10, Llp_vslot
	ldr	w10, [x28, #G_AONLY]      ; a broadcast's picture: its HLS, straight from YouTube
	cbnz	w10, Llp_sound
	ADDO	x0, x20, JOB_VURL
	b	Llp_item
Llp_vslot:
	ADDO	x0, x20, JOB_VURL
	mov	w1, #SLOT_VIDEO
	CSTR	x2, "127.0.0.1"
	ADDO	x3, x20, JOB_VLOCAL
	bl	slot_uri
Llp_hls:
	ldr	w9, [x20, #JOB_LIVE]
	cbnz	w9, Llp_sound             ; a broadcast has no index: it plays as it comes
	mov	x0, x20                   ; the picture's too, even for Audio Only, which can be turned off later
	CSTR	x1, "127.0.0.1"
	bl	hls_master
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, Llp_sound
	ADDO	x9, x20, JOB_HLS
	ldrb	w9, [x9]
	ADDO	x0, x20, JOB_HLS
	cbnz	w9, Llp_item
Llp_sound:
	ADDO	x9, x20, JOB_HLSA
	ldrb	w9, [x9]
	ADDO	x0, x20, JOB_HLSA
	cbnz	w9, Llp_item
	ADDO	x0, x20, JOB_LOCAL
Llp_item:
	bl	make_item
	str	x0, [x20, #JOB_ITEM]
	b	Lret2

; mkurl(cstr) -> an autoreleased NSURL, or nil.
mkurl:
	FRAME	0
	bl	mkstr
	mov	x2, x0
	CLASS	x0, NSURL
	SEND	S_URLWithString_
	b	Lret0

; make_item(url) -> a retained AVPlayerItem for a URL string, or nil if it is not one.
make_item:
	FRAME	0
	bl	mkurl
	cbz	x0, Lret0
	mov	x2, x0
	CLASS	x0, AVPlayerItem
	SEND	S_playerItemWithURL_
	SEND	S_retain
	b	Lret0

; hls_master(job, host) — JOB_HLSA: the sound as HLS, segmented by its index; then, with a picture (JOB_VLOCAL), JOB_HLS: a master playlist with the picture as its one variant and that sound as its audio. Each stays "" if its index did not come.
	.equ HX_V,	48                ; char[256], the picture's playlist
	.equ HX_TEXT,	304               ; char*
	.equ HX_SIZE,	320
hls_master:
	FRAME	3, HX_SIZE
	mov	x20, x0
	mov	x23, x1
	bl	curl_new
	mov	x19, x0
	cbz	x0, Lret2
	add	x0, x20, #JOB_URL
	ADDO	x1, x20, JOB_LOCAL
	add	x2, x20, #JOB_AFMT
	ADDO	x3, x20, JOB_HLSA
	mov	x4, x23
	bl	hls_media
	cbz	w0, Lhx_done
	ADDO	x9, x20, JOB_VLOCAL
	ldrb	w9, [x9]
	cbz	w9, Lhx_done              ; sound only
	ADDO	x0, x20, JOB_VURL
	ADDO	x1, x20, JOB_VLOCAL
	add	x2, x20, #JOB_VFMT
	add	x3, sp, #HX_V
	mov	x4, x23
	bl	hls_media
	cbz	w0, Lhx_done
	ADDO	x9, x20, JOB_HLSA
	ldr	x10, [x20, #(JOB_VFMT + FMT_RATE)]
	ldr	x11, [x20, #(JOB_AFMT + FMT_RATE)]
	add	x10, x10, x11
	stp	x9, x10, [sp]
	add	x9, x20, #(JOB_VFMT + FMT_CODECS)
	add	x10, x20, #(JOB_AFMT + FMT_CODECS)
	stp	x9, x10, [sp, #16]
	add	x9, sp, #HX_V
	str	x9, [sp, #32]
	add	x0, sp, #HX_TEXT
	CSTR	x1, "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",NAME=\"Sound\",DEFAULT=YES,AUTOSELECT=YES,URI=\"%s\"\n#EXT-X-STREAM-INF:BANDWIDTH=%llu,CODECS=\"%s,%s\",AUDIO=\"a\"\n%s\n"
	bl	_asprintf
	tbnz	w0, #31, Lhx_done
	ldr	x0, [sp, #HX_TEXT]
	mov	w1, #SLOT_SOUND
	mov	x2, x23
	ADDO	x3, x20, JOB_HLS
	bl	slot_uri
	ldr	x0, [sp, #HX_TEXT]
	bl	_free
Lhx_done:
	mov	x0, x19
	bl	_curl_easy_cleanup
	b	Lret3

; hls_media(upstream, local, fmt, out[256], host) — an HLS playlist of one fragmented MP4 stream, its segments read from the stream's sidx (fetched with the handle in x19); out = where it is served on host; w0 = 1 if built.
	.equ HM_BUF,	48                ; {data, len}: the sidx
	.equ HM_RANGE,	64                ; char[48]
	.equ HM_TEXT,	112               ; char*, the playlist
	.equ HM_CAP,	120               ; its size
	.equ HM_SCALE,	128               ; sidx timescale
	.equ HM_INIT,	136               ; init segment length
	.equ HM_HOST,	144               ; char *, where the playlist is served
	.equ HM_SIZE,	160
hls_media:
	FRAME	4, HM_SIZE
	mov	x20, x0
	mov	x21, x1
	mov	x23, x3
	str	x4, [sp, #HM_HOST]
	ldr	x9, [x2, #FMT_INIT]
	add	x9, x9, #1
	str	x9, [sp, #HM_INIT]
	ldp	x9, x10, [x2, #FMT_IDX0]
	add	x26, x10, #1              ; where the sidx ends
	mov	x22, #0                   ; built
	stp	xzr, xzr, [sp, #HM_BUF]
	cbz	x10, Lhl_free             ; no index
	stp	x9, x10, [sp]
	add	x0, sp, #HM_RANGE
	mov	x1, #48
	GADDR	x2, Ls_range
	bl	_snprintf
	add	x2, sp, #HM_RANGE
	mov	w1, #CURLOPT_RANGE
	bl	copt
	mov	x0, x20
	mov	x1, #0
	mov	x2, #0
	add	x3, sp, #HM_BUF
	mov	x4, #API_TIMEOUT_MS
	bl	http
	mov	w24, w0
	mov	x2, #0
	mov	w1, #CURLOPT_RANGE
	bl	copt
	cbz	w24, Lhl_free
	ldp	x24, x9, [sp, #HM_BUF]
	add	x25, x24, x9              ; the data's end
	cmp	x9, #32
	b.lo	Lhl_free
	ldr	w9, [x24, #4]
	mov	w10, #0x6973
	movk	w10, #0x7864, lsl #16     ; "sidx"
	cmp	w9, w10
	b.ne	Lhl_free
	ldr	w9, [x24, #16]
	rev	w9, w9
	cbz	w9, Lhl_free
	str	x9, [sp, #HM_SCALE]
	ldrb	w9, [x24, #8]             ; version: 32- or 64-bit times and offset
	cbnz	w9, Lhl_v1
	ldr	w10, [x24, #24]
	rev	w10, w10
	ldrh	w20, [x24, #30]
	add	x24, x24, #32
	b	Lhl_refs
Lhl_v1:
	add	x9, x24, #40
	cmp	x9, x25
	b.hi	Lhl_free
	ldr	x10, [x24, #28]
	rev	x10, x10
	ldrh	w20, [x24, #38]
	add	x24, x24, #40
Lhl_refs:
	rev16	w20, w20                  ; references
	add	x26, x26, x10             ; the first segment's offset
	mov	x9, #12
	madd	x9, x20, x9, x24
	cmp	x9, x25
	b.hi	Lhl_free                  ; cut short
	mov	x25, x24                  ; the references
	mov	x0, x21                   ; room: 80 bytes and the URL per segment
	bl	_strlen
	add	x9, x0, #80
	mul	x9, x9, x20
	add	x0, x9, x0
	add	x0, x0, #512
	str	x0, [sp, #HM_CAP]
	bl	_malloc
	cbz	x0, Lhl_free
	str	x0, [sp, #HM_TEXT]
	mov	x9, #0                    ; the longest segment, for the target duration
	mov	x10, #0
Lhl_max:
	cmp	x10, x20
	b.hs	Lhl_head
	mov	x11, #12
	madd	x11, x10, x11, x25
	ldr	w11, [x11, #4]
	rev	w11, w11
	cmp	x11, x9
	csel	x9, x11, x9, hi
	add	x10, x10, #1
	b	Lhl_max
Lhl_head:
	ldr	x10, [sp, #HM_SCALE]
	add	x9, x9, x10
	sub	x9, x9, #1
	udiv	x9, x9, x10               ; rounded up
	stp	x9, x21, [sp]
	ldr	x9, [sp, #HM_INIT]
	str	x9, [sp, #16]
	ldr	x0, [sp, #HM_TEXT]
	ldr	x1, [sp, #HM_CAP]
	CSTR	x2, "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:%llu\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MAP:URI=\"%s\",BYTERANGE=\"%llu@0\"\n"
	bl	_snprintf
	ldr	x24, [sp, #HM_TEXT]
	add	x24, x24, w0, sxtw        ; the write cursor
Lhl_seg:
	cbz	x20, Lhl_end
	sub	x20, x20, #1
	ldp	w9, w10, [x25], #12
	rev	w9, w9
	and	w9, w9, #0x7fffffff       ; referenced size
	rev	w10, w10                  ; duration, in timescale units
	mov	x11, #1000
	mul	x10, x10, x11
	ldr	x11, [sp, #HM_SCALE]
	udiv	x10, x10, x11             ; milliseconds
	mov	x11, #1000
	udiv	x12, x10, x11
	msub	x13, x12, x11, x10
	stp	x12, x13, [sp]
	stp	x9, x26, [sp, #16]
	str	x21, [sp, #32]
	add	x26, x26, x9
	mov	x0, x24
	ldp	x9, x10, [sp, #HM_TEXT]
	add	x1, x9, x10
	sub	x1, x1, x24               ; room left
	CSTR	x2, "#EXTINF:%llu.%03llu,\n#EXT-X-BYTERANGE:%llu@%llu\n%s\n"
	bl	_snprintf
	add	x24, x24, w0, sxtw
	b	Lhl_seg
Lhl_end:
	mov	x0, x24
	ldp	x9, x10, [sp, #HM_TEXT]
	add	x1, x9, x10
	sub	x1, x1, x24
	CSTR	x2, "#EXT-X-ENDLIST\n"
	bl	_snprintf
	ldr	x0, [sp, #HM_TEXT]
	mov	w1, #SLOT_SOUND
	ldr	x2, [sp, #HM_HOST]
	mov	x3, x23
	bl	slot_uri
	ldr	x0, [sp, #HM_TEXT]
	bl	_free
	mov	x22, #1
Lhl_free:
	ldr	x0, [sp, #HM_BUF]
	bl	_free
	mov	w0, w22
	b	Lret4

; slot_uri(source, kind, host, out[256]) — serve a media URL or file path under a fresh random token; out = its URL on host.
slot_uri:
	FRAME	3, 96
	mov	x19, x0
	mov	w22, w1
	mov	x20, x2
	mov	x21, x3
	mov	x0, sp                    ; 128 random bits, printed as 32 hex digits
	mov	x1, #16
	bl	_arc4random_buf
	add	x0, sp, #48
	mov	x1, #TOKEN_STRIDE
	CSTR	x2, "%016llx%016llx"
	bl	_snprintf
	cmp	w22, #SLOT_LIVE
	cset	w9, eq
	strb	w9, [sp, #(48 + TOKEN_STRIDE - 1)] ; a slot's last byte flags a live broadcast
	LOCK
	ldr	w23, [x28, #G_SLOTI]
	add	w9, w23, #1
	and	w9, w9, #(SLOTS - 1)
	str	w9, [x28, #G_SLOTI]
	BADDR	x0, B_SLOTTOK
	mov	x9, #TOKEN_STRIDE
	madd	x0, x23, x9, x0
	add	x1, sp, #48
	mov	x2, #TOKEN_STRIDE
	bl	_memcpy
	add	x24, x28, #G_SLOTURL
	ldr	x0, [x24, x23, lsl #3]
	bl	_free                     ; the oldest stream is retired
	mov	x0, x19
	bl	_strdup
	str	x0, [x24, x23, lsl #3]
	UNLOCK
	CSTR	x10, "m4a"                ; a name the device can tell the format from
	CSTR	x11, "aac"
	cmp	w22, #SLOT_LIVE
	csel	x10, x11, x10, eq
	CSTR	x11, "mp4"
	cmp	w22, #SLOT_VIDEO
	csel	x10, x11, x10, eq
	ldrb	w9, [x19]
	CSTR	x11, "m3u8"
	cmp	w9, #'#'
	csel	x10, x11, x10, eq         ; a playlist made here
	cmp	w9, #'/'
	b.ne	Lsl_print
	mov	x0, x19                   ; a file keeps its own extension
	mov	w1, #'.'
	bl	_strrchr
	CSTR	x10, "bin"
	cbz	x0, Lsl_print
	add	x10, x0, #1
Lsl_print:
	ldr	w9, [x28, #G_PORT]
	stp	x20, x9, [sp]
	add	x9, sp, #48
	stp	x9, x10, [sp, #16]
	mov	x0, x21
	mov	x1, #256
	CSTR	x2, "http://%s:%u/stream/%s.%s"
	bl	_snprintf
	b	Lret3

; play_upnp(job) — serve the media (a web address goes as it is) and play it on the device with DIDL-Lite metadata.
	ENTRY	play_upnp
	FRAME	4, 64
	mov	x19, x0
	ldr	w25, [x19, #JOB_KIND]
	cmp	w25, #KIND_WEB
	b.ne	Lps_serve
	BADDR	x0, B_MYURI
	add	x1, x19, #JOB_URL
	mov	x2, #MYURI_SIZE
	bl	_strlcpy
	CSTR	x26, "*"
	b	Lps_track
Lps_serve:
	add	x0, x19, #JOB_URL
	ldr	w1, [x19, #JOB_LIVE]
	GADDR	x26, Ls_mp4
	cbz	w1, Lps_tv
	GADDR	x26, Ls_aac
	b	Lps_kind
Lps_tv:
	BADDR	x9, B_CUR
	ldrb	w20, [x9, #DEV_VIDEO]
	tbz	w20, #1, Lps_mp4          ; a TV that plays HLS gets Beam's presentation, at full quality
	ADDO	x9, x19, JOB_VURL
	ldrb	w9, [x9]
	cbz	w9, Lps_mp4
	add	x0, x19, #JOB_URL
	mov	w1, #SLOT_SOUND
	BADDR	x2, B_LANIP
	ADDO	x3, x19, JOB_LOCAL
	bl	slot_uri
	ADDO	x0, x19, JOB_VURL
	mov	w1, #SLOT_VIDEO
	BADDR	x2, B_LANIP
	ADDO	x3, x19, JOB_VLOCAL
	bl	slot_uri
	mov	x0, x19
	BADDR	x1, B_LANIP
	bl	hls_master
	ADDO	x1, x19, JOB_HLS
	ldrb	w9, [x1]
	cbz	w9, Lps_mp4
	BADDR	x0, B_MYURI
	mov	x2, #MYURI_SIZE
	bl	_strlcpy
	GADDR	x26, Ls_hls
	b	Lps_track
Lps_mp4:
	add	x0, x19, #JOB_URL         ; the sound, unless a TV gets picture and sound in one MP4 (when YouTube offers it)
	mov	w1, #SLOT_SOUND
	tbz	w20, #0, Lps_kind
	ADDO	x9, x19, JOB_MURL
	ldrb	w10, [x9]
	cbz	w10, Lps_kind
	mov	x0, x9
	mov	w1, #SLOT_VIDEO
	CSTR	x26, "video/mp4"
	b	Lps_slot
Lps_kind:
	cmp	w25, #KIND_FILE
	b.ne	Lps_slot
	ldr	x0, [x19, #JOB_QUERY]     ; a file: the proxy reads it from disk
	bl	mime_of
	mov	x26, x0
	ldr	x0, [x19, #JOB_QUERY]
	mov	w1, #SLOT_SOUND
Lps_slot:
	BADDR	x2, B_LANIP
	BADDR	x3, B_MYURI
	bl	slot_uri
Lps_track:
	BADDR	x0, B_MYTRACK
	add	x1, x19, #JOB_TRACK
	mov	x2, #T_SIZE
	bl	_memcpy
	ldr	x9, [x19, #JOB_DUR]
	str	x9, [x28, #G_MYDUR]
	add	x0, x19, #(JOB_TRACK + T_TITLE)
	bl	xml_escape
	mov	x20, x0
	add	x0, x19, #(JOB_TRACK + T_ARTIST)
	bl	xml_escape
	mov	x21, x0
	add	x0, x19, #(JOB_TRACK + T_ART)
	bl	xml_escape
	mov	x22, x0
	BADDR	x0, B_MYURI
	bl	xml_escape
	mov	x23, x0
	stp	x20, x21, [sp]
	str	x22, [sp, #16]
	CSTR	x9, "audio"               ; a picture plays as a video item (TVs)
	CSTR	x10, "video"
	ldrb	w11, [x26]
	cmp	w11, #'v'
	GADDR	x11, Ls_hls
	ccmp	x26, x11, #4, ne
	csel	x9, x10, x9, eq
	stp	x9, x26, [sp, #24]
	str	x23, [sp, #40]
	add	x0, sp, #48
	CSTR	x1, "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\"><item id=\"-1\" parentID=\"-1\" restricted=\"true\"><dc:title>%s</dc:title><dc:creator>%s</dc:creator><upnp:albumArtURI>%s</upnp:albumArtURI><upnp:class>object.item.%sItem</upnp:class><res protocolInfo=\"http-get:*:%s:*\">%s</res></item></DIDL-Lite>"
	bl	_asprintf
	mov	x0, x20
	bl	_free
	mov	x0, x21
	bl	_free
	mov	x0, x22
	bl	_free
	mov	w22, #PLAY_REJECTED
	ldr	x20, [sp, #48]
	cbz	x20, Lps_done
	mov	x0, x20
	bl	xml_escape                ; the DIDL travels as text inside SOAP
	mov	x21, x0
	mov	x0, x20
	bl	_free
	cbz	x21, Lps_done
	stp	x23, x21, [sp]
	add	x0, sp, #48
	CSTR	x1, "<CurrentURI>%s</CurrentURI><CurrentURIMetaData>%s</CurrentURIMetaData>"
	bl	_asprintf
	mov	x0, x21
	bl	_free
	ldr	x20, [sp, #48]
	cbz	x20, Lps_done
	CSTR	x0, "SetAVTransportURI"
	mov	x1, x20
	bl	avcmd
	mov	w21, w0
	mov	x0, x20
	bl	_free
	cbz	w21, Lps_done
	GADDR	x0, Ls_play
	GADDR	x1, Ls_speed
	bl	avcmd
	mov	w22, #PLAY_OK
Lps_done:
	mov	x0, x23
	bl	_free
	str	w22, [x19, #JOB_RESULT]
	bl	poll_now                  ; show the new track right away
	b	Lret4

; ---- Audio proxy: streams the media to the speaker ----

; respond(fd, status, message) — a complete plain-text response, e.g. status "404 Not Found".
respond:
	FRAME	2, 560
	mov	w19, w0
	mov	x20, x2
	str	x1, [sp]
	mov	x0, x2
	bl	_strlen
	stp	x0, x20, [sp, #8]
	add	x0, sp, #48
	mov	x1, #512
	CSTR	x2, "HTTP/1.1 %s\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %zu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n%s"
	bl	_snprintf
	mov	w2, w0
	mov	w0, w19
	add	x1, sp, #48
	bl	send_all
	b	Lret2

; proxy_reply(proxy) — check an upstream answer; the first one also sends the speaker its response head.
	.equ PR_HDR,	48                ; struct curl_header *
	.equ PR_START,	56                ; Content-Range first byte
	.equ PR_LAST,	64                ; last byte
	.equ PR_TOTAL,	72                ; total length
	.equ PR_TYPE,	80                ; char *, Content-Type
	.equ PR_HEAD,	96                ; char[512], response head
	.equ PR_SIZE,	608
proxy_reply:
	FRAME	1, PR_SIZE
	mov	x19, x0
	ldr	x0, [x19, #PX_CURL]
	bl	status_of
	cmp	x0, #206
	b.ne	Lpy_no                    ; byte ranges only: whole-file reads are throttled
	ldr	w9, [x19, #PX_SENT]
	cbnz	w9, Lpy_yes               ; a later chunk of the same response
	ldr	x0, [x19, #PX_CURL]
	CSTR	x1, "Content-Range"
	mov	x2, #0
	mov	w3, #CURLH_HEADER
	mov	w4, #-1                   ; the last request, after redirects
	add	x5, sp, #PR_HDR
	bl	_curl_easy_header
	cbnz	w0, Lpy_no
	ldr	x9, [sp, #PR_HDR]
	ldr	x0, [x9, #8]              ; "bytes first-last/total"
	add	x9, sp, #PR_START
	add	x10, sp, #PR_LAST
	stp	x9, x10, [sp]
	add	x9, sp, #PR_TOTAL
	str	x9, [sp, #16]
	CSTR	x1, "bytes %lld-%lld/%lld"
	bl	_sscanf
	cmp	w0, #3
	b.ne	Lpy_no
	ldr	x9, [sp, #PR_START]
	str	x9, [x19, #PX_POS]        ; a suffix range learns its first byte here
	ldr	x10, [sp, #PR_TOTAL]
	sub	x10, x10, #1
	ldr	x11, [x19, #PX_END]
	cmp	x11, x10
	csel	x11, x11, x10, lt
	str	x11, [x19, #PX_END]       ; never past the end of the file
	str	xzr, [sp, #PR_TYPE]
	add	x9, sp, #PR_TYPE
	str	x9, [sp]
	ldr	x0, [x19, #PX_CURL]
	mov	w1, #(CURLINFO_CONTENT_TYPE & 0xffff)
	movk	w1, #(CURLINFO_CONTENT_TYPE >> 16), lsl #16
	bl	_curl_easy_getinfo
	ldr	x9, [sp, #PR_TYPE]
	GADDR	x10, Ls_mp4
	cmp	x9, #0
	csel	x9, x9, x10, ne
	ldr	x10, [sp, #PR_TOTAL]
	ldr	w11, [x19, #PX_RANGED]
	cbnz	w11, Lpy_partial
	stp	x9, x10, [sp]
	GADDR	x2, Ls_200
	b	Lpy_print
Lpy_partial:
	ldp	x11, x12, [x19, #PX_POS]
	sub	x13, x12, x11
	add	x13, x13, #1
	stp	x9, x13, [sp]
	stp	x11, x12, [sp, #16]
	str	x10, [sp, #32]
	GADDR	x2, Ls_206
Lpy_print:
	add	x0, sp, #PR_HEAD
	mov	x1, #512
	bl	_snprintf
	cmp	w0, #512
	b.hs	Lpy_no                    ; truncated
	mov	w2, w0
	ldr	w0, [x19, #PX_FD]
	add	x1, sp, #PR_HEAD
	bl	send_all
	cbz	w0, Lpy_no
	mov	w9, #1
	str	w9, [x19, #PX_SENT]
Lpy_yes:
	mov	w0, #1
	b	Lret1
Lpy_no:
	mov	w0, #0
	b	Lret1

; proxy_body(data, size, nmemb, proxy) — forward media bytes; 0 stops the transfer.
	ENTRY	proxy_body
	FRAME	2
	mov	x19, x0
	mul	x20, x1, x2
	mov	x21, x3
	ldr	w9, [x21, #PX_BROKEN]
	cbnz	w9, Lpb_stop
	ldr	w9, [x21, #PX_CHECKED]
	cbnz	w9, Lpb_send
	mov	w9, #1
	str	w9, [x21, #PX_CHECKED]
	mov	x0, x21
	bl	proxy_reply
	cbz	w0, Lpb_broken
	ldr	w9, [x21, #PX_HEAD]
	cbnz	w9, Lpb_stop              ; HEAD: the response head was all it wanted
Lpb_send:
	ldr	w0, [x21, #PX_FD]
	mov	x1, x19
	mov	x2, x20
	bl	send_all
	cbz	w0, Lpb_broken
	ldr	x9, [x21, #PX_POS]
	add	x9, x9, x20
	str	x9, [x21, #PX_POS]
	mov	x0, x20
	b	Lret2
Lpb_broken:
	mov	w9, #1
	str	w9, [x21, #PX_BROKEN]
Lpb_stop:
	mov	x0, #0
	b	Lret2

; vod_stream(fd, url, range, head, slot) — proxy a media file in chunks the CDN serves at full speed, honoring the speaker's range; the slot then keeps the address the CDN redirected to, so later requests go straight there.
	.equ VS_PX,	16                ; proxy state
	.equ VS_RANGE,	VS_PX + PX_SIZE   ; char[32], upstream range
	.equ VS_A,	VS_RANGE + 32     ; the speaker's first byte
	.equ VS_B,	VS_A + 8          ; and last byte
	.equ VS_SLOT,	VS_B + 8          ; char **, the slot's URL
	.equ VS_EFF,	VS_SLOT + 8       ; char *, where the CDN sent us
	.equ VS_SIZE,	VS_EFF + 8
vod_stream:
	FRAME	4, VS_SIZE
	mov	w20, w0
	mov	x21, x1
	mov	x22, x2
	mov	w24, w3
	str	x4, [sp, #VS_SLOT]
	bl	curl_new
	mov	x19, x0
	cbz	x0, Lret4                 ; out of memory: the speaker sees the connection close
	add	x25, sp, #VS_PX
	stp	xzr, xzr, [x25]
	stp	xzr, xzr, [x25, #16]
	stp	xzr, xzr, [x25, #32]
	str	w20, [x25, #PX_FD]
	str	w24, [x25, #PX_HEAD]
	str	x19, [x25, #PX_CURL]
	mov	x9, #0x7fffffffffffffff
	str	x9, [x25, #PX_END]        ; open-ended until the first answer gives the size
	mov	x0, x22
	add	x1, sp, #VS_A
	bl	range_of
	cmp	w0, #1
	b.lt	Lvs_setup                 ; none or unreadable: the whole file from byte 0
	mov	w9, #1
	str	w9, [x25, #PX_RANGED]
	ldr	x9, [sp, #VS_A]
	str	x9, [x25, #PX_POS]        ; negative for a suffix ("-500")
	cmp	w0, #2
	b.ne	Lvs_suffix
	ldr	x10, [sp, #VS_B]
	str	x10, [x25, #PX_END]
Lvs_suffix:
	tbz	x9, #63, Lvs_setup
	mov	x0, x22
	mov	w1, #'-'
	bl	_strchr
	mov	x22, x0                   ; "-n", as libcurl takes it
	mov	x0, x21                   ; the CDN refuses suffixes: count back from the size in the URL
	CSTR	x1, "clen="
	bl	_strstr
	cbz	x0, Lvs_setup
	add	x0, x0, #5
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	ldr	x9, [x25, #PX_POS]
	adds	x9, x0, x9
	csel	x9, x9, xzr, gt
	str	x9, [x25, #PX_POS]
Lvs_setup:
	mov	x2, x21
	mov	w1, #CURLOPT_URL
	bl	copt
	mov	w1, #CURLOPT_NOSIGNAL
	bl	copt1
	mov	w1, #CURLOPT_FOLLOWLOCATION
	bl	copt1
	mov	w1, #CURLOPT_FAILONERROR      ; error pages never reach the speaker
	bl	copt1
	adr	x2, proxy_body
	mov	w1, #CURLOPT_WRITEFUNCTION
	bl	copt
	mov	x2, x25
	mov	w1, #CURLOPT_WRITEDATA
	bl	copt
	mov	x2, #PROXY_BUFFER
	mov	w1, #CURLOPT_BUFFERSIZE
	bl	copt
	CSTR	x2, "identity"            ; the bytes must match the ranges
	mov	w1, #CURLOPT_ACCEPT_ENCODING
	bl	copt
Lvs_chunk:
	ldr	x9, [x25, #PX_POS]
	mov	x2, x22                   ; a suffix of unknown size goes as the speaker wrote it
	tbnz	x9, #63, Lvs_range
	mov	x10, #CHUNK
	add	x10, x9, x10
	sub	x10, x10, #1
	ldr	x11, [x25, #PX_END]
	cmp	x10, x11
	csel	x10, x10, x11, lt         ; one chunk, never past the last byte
	stp	x9, x10, [sp]
	add	x0, sp, #VS_RANGE
	mov	x1, #32
	GADDR	x2, Ls_range
	bl	_snprintf
	add	x2, sp, #VS_RANGE
Lvs_range:
	mov	w1, #CURLOPT_RANGE
	bl	copt
	str	wzr, [x25, #PX_CHECKED]
	ldr	x26, [x25, #PX_POS]       ; to tell progress from a dead end
	mov	x0, x19
	bl	_curl_easy_perform
	ldr	w9, [x25, #PX_SENT]
	cbz	w9, Lvs_refused
	ldr	x9, [sp, #VS_SLOT]        ; the first good answer: keep the CDN's final address in the slot
	cbz	x9, Lvs_known
	str	xzr, [sp, #VS_EFF]
	add	x9, sp, #VS_EFF
	str	x9, [sp]
	mov	x0, x19
	mov	w1, #(CURLINFO_EFFECTIVE_URL & 0xffff)
	movk	w1, #(CURLINFO_EFFECTIVE_URL >> 16), lsl #16
	bl	_curl_easy_getinfo
	ldr	x0, [sp, #VS_EFF]
	cbz	x0, Lvs_once
	mov	x1, x21
	bl	_strcmp
	cbz	w0, Lvs_once              ; not redirected
	ldr	x0, [sp, #VS_EFF]
	bl	_strdup
	str	x0, [sp, #VS_EFF]
	LOCK
	ldr	x9, [sp, #VS_SLOT]
	ldr	x0, [x9]
	cbz	x0, Lvs_moved
	mov	x1, x21
	bl	_strcmp
	cbnz	w0, Lvs_moved             ; the slot serves another stream now
	ldr	x9, [sp, #VS_SLOT]
	ldr	x0, [x9]
	bl	_free
	ldr	x9, [sp, #VS_SLOT]
	ldr	x10, [sp, #VS_EFF]
	str	x10, [x9]
	str	xzr, [sp, #VS_EFF]
Lvs_moved:
	UNLOCK
	ldr	x0, [sp, #VS_EFF]
	bl	_free
Lvs_once:
	str	xzr, [sp, #VS_SLOT]
Lvs_known:
	ldr	w9, [x25, #PX_BROKEN]
	orr	w9, w9, w24
	cbnz	w9, Lvs_done
	ldp	x9, x10, [x25, #PX_POS]
	cmp	x9, x10
	b.gt	Lvs_done                  ; all sent
	cmp	x9, x26
	b.ne	Lvs_chunk                 ; next chunk, or resume after a dropped connection
	b	Lvs_done                  ; no progress: give up
Lvs_refused:
	mov	x0, x19
	bl	status_of
	CSTR	x1, "502 Bad Gateway"
	cmp	x0, #416
	b.ne	Lvs_reply
	CSTR	x1, "416 Range Not Satisfiable"
Lvs_reply:
	mov	w0, w20
	GADDR	x2, Ls_slash+1
	bl	respond
Lvs_done:
	mov	x0, x19
	bl	_curl_easy_cleanup
	b	Lret4

; range_of(header, out[2]) -> how many of first and last byte a Range value gives ("bytes=a-b", "a-", "-n", or a bare "a-b"); a suffix reads as a negative first byte.
range_of:
	FRAME	1, 16
	mov	x19, x1
	mov	x20, x0
	ldrb	w9, [x0]
	cbz	w9, Lro_none
	CSTR	x1, "bytes="
	bl	_strcasestr
	add	x9, x20, #6
	cmp	x0, x20
	csel	x0, x9, x20, eq
	add	x9, x19, #8
	stp	x19, x9, [sp]
	GADDR	x1, Ls_range
	bl	_sscanf
	cmp	w0, #0
	csel	w0, w0, wzr, gt           ; EOF reads as none
	b	Lret1
Lro_none:
	mov	w0, #0
	b	Lret1

; mime_of(path) -> the media type of a file name's extension.
	.pushsection __DATA,__data
Lmimes:	                                  ; extension, then its type
	.asciz	"mp3", "audio/mpeg"
	.asciz	"m4a", "audio/mp4"
	.asciz	"m4b", "audio/mp4"
	.asciz	"aac", "audio/aac"
	.asciz	"flac", "audio/flac"
	.asciz	"wav", "audio/wav"
	.asciz	"aif", "audio/aiff"
	.asciz	"aiff", "audio/aiff"
	.asciz	"ogg", "audio/ogg"
	.asciz	"opus", "audio/ogg"
	.asciz	"mp4", "video/mp4"
	.asciz	"m4v", "video/mp4"
	.asciz	"mov", "video/quicktime"
	.byte	0
	.popsection
mime_of:
	FRAME	2
	mov	w1, #'.'
	bl	_strrchr
	cbz	x0, Lmo_none
	add	x19, x0, #1
	GADDR	x20, Lmimes
Lmo_next:
	ldrb	w9, [x20]
	cbz	w9, Lmo_none
	mov	x0, x19
	mov	x1, x20
	bl	_strcasecmp
	mov	w21, w0
	mov	x0, x20
	bl	nextstr
	cbz	w21, Lret2                ; its type
	bl	nextstr
	mov	x20, x0
	b	Lmo_next
Lmo_none:
	CSTR	x0, "application/octet-stream"
	b	Lret2

; text_stream(fd, text, head) — a playlist made here.
text_stream:
	FRAME	2, 160
	mov	w19, w0
	mov	x20, x1
	mov	w21, w2
	mov	x0, x20
	bl	_strlen
	mov	x22, x0
	str	x0, [sp]
	add	x0, sp, #16
	mov	x1, #144
	CSTR	x2, "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: %zu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
	bl	_snprintf
	mov	w2, w0
	mov	w0, w19
	add	x1, sp, #16
	bl	send_all
	cbz	w0, Lret2
	cbnz	w21, Lret2                ; HEAD
	mov	w0, w19
	mov	x1, x20
	mov	x2, x22
	bl	send_all
	b	Lret2

; file_stream(fd, path, range, head) — serve a file on this Mac, honoring the speaker's range, straight from disk to the socket.
	.equ FS_AB,	48                ; first and last byte asked; then sendfile's count (after snprintf's five arguments)
	.equ FS_HEAD,	64                ; char[512]
	.equ FS_SIZE,	FS_HEAD + 512
file_stream:
	FRAME	4, FS_SIZE
	mov	w19, w0
	mov	x20, x1
	mov	x21, x2
	mov	w22, w3
	mov	x0, x20
	mov	w1, #0                    ; O_RDONLY
	bl	_open
	mov	w23, w0
	tbnz	w0, #31, Lfs_gone
	mov	x1, #0
	mov	w2, #2                    ; SEEK_END: the size
	bl	_lseek
	mov	x24, x0
	mov	x0, x21
	add	x1, sp, #FS_AB
	bl	range_of
	mov	w25, w0                   ; asked for a range
	mov	x26, #0                   ; first byte
	sub	x21, x24, #1              ; last byte
	cbz	w25, Lfs_span
	ldp	x9, x10, [sp, #FS_AB]
	mov	x26, x9
	tbz	x9, #63, Lfs_last
	adds	x26, x24, x9              ; a suffix: the last n bytes
	csel	x26, x26, xzr, gt
	b	Lfs_span
Lfs_last:
	cmp	w25, #2
	b.ne	Lfs_span
	cmp	x10, x21
	csel	x21, x10, x21, lt
Lfs_span:
	cmp	x26, x21
	b.gt	Lfs_416                   ; past the end (or an empty file)
	mov	x0, x20
	bl	mime_of
	sub	x9, x21, x26
	add	x9, x9, #1                ; bytes to send
	stp	x0, x9, [sp]
	GADDR	x2, Ls_200
	cbz	w25, Lfs_print
	stp	x26, x21, [sp, #16]
	str	x24, [sp, #32]
	GADDR	x2, Ls_206
Lfs_print:
	add	x0, sp, #FS_HEAD
	mov	x1, #512
	bl	_snprintf
	cmp	w0, #512
	b.hs	Lfs_close
	mov	w2, w0
	mov	w0, w19
	add	x1, sp, #FS_HEAD
	bl	send_all
	cbz	w0, Lfs_close
	cbnz	w22, Lfs_close            ; HEAD: the response head was all it wanted
Lfs_send:
	sub	x9, x21, x26
	add	x9, x9, #1
	str	x9, [sp, #FS_AB]          ; in: how many, out: how many went
	mov	w0, w23
	mov	w1, w19
	mov	x2, x26
	add	x3, sp, #FS_AB
	mov	x4, #0
	mov	w5, #0
	bl	_sendfile
	ldr	x9, [sp, #FS_AB]
	add	x26, x26, x9
	cmp	x26, x21
	b.gt	Lfs_close                 ; all sent
	cbnz	x9, Lfs_send              ; part of it: the rest
	b	Lfs_close                 ; none: the speaker went away
Lfs_416:
	mov	w0, w19
	CSTR	x1, "416 Range Not Satisfiable"
	GADDR	x2, Ls_slash+1
	bl	respond
Lfs_close:
	mov	w0, w23
	bl	_close
	b	Lret4
Lfs_gone:
	mov	w0, w19
	GADDR	x1, Ls_404
	CSTR	x2, "file not found"
	bl	respond
	b	Lret4

; box_find(p, end, type) — x0 = the payload of the first box of that type in [p, end), x1 = its end; x0 = 0 if none.
box_find:
	add	x9, x0, #8
	cmp	x9, x1
	b.hi	Lbf_none
	ldr	w10, [x0]
	rev	w10, w10                  ; size, big-endian
	cmp	w10, #8
	b.lo	Lbf_none
	add	x11, x0, x10
	cmp	x11, x1
	b.hi	Lbf_none
	ldr	w12, [x0, #4]
	mov	x0, x11
	cmp	w12, w2
	b.ne	box_find
	mov	x0, x9
	mov	x1, x11
	ret
Lbf_none:
	mov	x0, #0
	ret

; box_path(p, end, path) — follow a path of {type, bytes to skip} words from [p, end); x0 = where it ends (0 if absent), x1 = the last box's end.
box_path:
	stp	x19, x30, [sp, #-16]!
	mov	x19, x2
Lbp_next:
	ldp	w2, w3, [x19], #8
	cbz	w2, Lbp_done
	bl	box_find
	cbz	x0, Lbp_done
	add	x0, x0, x3
	b	Lbp_next
Lbp_done:
	ldp	x19, x30, [sp], #16
	ret

; desc_skip(p) -> past an MPEG-4 descriptor's tag and length, never reading at or past adts_send's esds end (x22).
desc_skip:
	add	x0, x0, #1
Lds_len:
	cmp	x0, x22
	b.hs	Lds_ret
	ldrb	w9, [x0], #1
	tbnz	w9, #7, Lds_len
Lds_ret:
	ret

	.pushsection __DATA,__data
Lesds_path:	                          ; segment -> AAC AudioSpecificConfig
	.ascii	"moov"
	.long	0
	.ascii	"trak"
	.long	0
	.ascii	"mdia"
	.long	0
	.ascii	"minf"
	.long	0
	.ascii	"stbl"
	.long	0
	.ascii	"stsd"
	.long	8                         ; version, flags, entry count
	.ascii	"mp4a"
	.long	28                        ; the audio sample entry's own fields
	.ascii	"esds"
	.long	4                         ; version, flags
	.quad	0
Ltrun_path:	                          ; moof -> the frame sizes
	.ascii	"traf"
	.long	0
	.ascii	"trun"
	.long	0
	.quad	0
	.popsection

; adts_send(fd, segment, len) — send the AAC frames of one fragmented MP4 segment as ADTS; w0 = 0 when the speaker went away or none could be read.
	.equ AD_COUNT,	0                 ; frames left
	.equ AD_STRIDE,	8                 ; bytes per trun sample record
	.equ AD_OUT,	16                ; ADTS write cursor
	.equ AD_SENT,	24                ; bytes sent from this segment
adts_send:
	FRAME	4, 32
	str	xzr, [sp, #AD_SENT]
	mov	w19, w0
	mov	x20, x1
	add	x21, x1, x2
	mov	x0, x20
	mov	x1, x21
	GADDR	x2, Lesds_path
	bl	box_path
	cbz	x0, Lad_ok
	mov	x22, x1
	bl	desc_skip                 ; ES_Descriptor
	add	x0, x0, #3                ; ES_ID, flags
	bl	desc_skip                 ; DecoderConfigDescriptor
	add	x0, x0, #13
	bl	desc_skip                 ; DecoderSpecificInfo: the AudioSpecificConfig
	add	x9, x0, #2
	cmp	x9, x22
	b.hi	Lad_ok
	ldrh	w9, [x0]
	rev16	w9, w9
	ubfx	w10, w9, #7, #4           ; sampling frequency index
	ubfx	w11, w9, #3, #4           ; channel configuration
	lsl	w23, w10, #2
	orr	w23, w23, w11, lsr #2
	orr	w23, w23, #0x40           ; profile: AAC LC
	bfi	w23, w11, #14, #2
	lsl	w23, w23, #16             ; header bytes 2-3
	mov	w9, #0xf1ff               ; sync word, MPEG-4, no CRC
	orr	w23, w23, w9
Lad_frag:
	mov	x0, x20
	mov	x1, x21
	mov	w2, #0x6f6d               ; "moof"
	movk	w2, #0x666f, lsl #16
	bl	box_find
	cbz	x0, Lad_ok
	mov	x24, x1
	GADDR	x2, Ltrun_path
	bl	box_path
	cbz	x0, Lad_ok
	add	x9, x0, #8
	cmp	x9, x1
	b.hi	Lad_ok                    ; no room for its flags and count
	ldr	w9, [x0]
	rev	w9, w9                    ; trun flags
	ldr	w10, [x0, #4]
	rev	w10, w10                  ; sample count
	add	x26, x0, #8
	tbz	w9, #0, 1f
	add	x26, x26, #4              ; data offset
1:	tbz	w9, #2, 1f
	add	x26, x26, #4              ; first sample flags
1:	tbz	w9, #9, Lad_ok            ; no frame sizes: nothing to split
	ubfx	w11, w9, #8, #4
	fmov	s0, w11
	cnt	v0.8b, v0.8b
	fmov	w11, s0
	lsl	w11, w11, #2              ; bytes per sample record
	madd	x13, x10, x11, x26        ; where the records end
	ubfx	w12, w9, #8, #1
	add	x26, x26, x12, lsl #2     ; the size field
	cmp	x13, x1
	b.hi	Lad_ok                    ; records past the box
	stp	x10, x11, [sp, #AD_COUNT]
	mov	x0, x24
	mov	x1, x21
	mov	w2, #0x646d               ; "mdat"
	movk	w2, #0x7461, lsl #16
	bl	box_find
	cbz	x0, Lad_ok
	mov	x24, x0
	mov	x25, x1
	mov	x20, x1                   ; the next fragment starts after this mdat
	ldr	x10, [sp, #AD_COUNT]
	sub	x9, x25, x24
	add	x0, x9, x10, lsl #3
	bl	_malloc
	mov	x22, x0
	cbz	x0, Lad_ok
	str	x0, [sp, #AD_OUT]
Lad_frame:
	ldr	x10, [sp, #AD_COUNT]
	cbz	x10, Lad_flush
	sub	x10, x10, #1
	str	x10, [sp, #AD_COUNT]
	ldr	w2, [x26]
	rev	w2, w2                    ; frame size
	ldr	x11, [sp, #AD_STRIDE]
	add	x26, x26, x11
	add	x9, x24, x2
	cmp	x9, x25
	b.hi	Lad_flush                 ; past the mdat
	add	w9, w2, #7                ; ADTS frame length
	cmp	w9, #0x2000
	b.hs	Lad_flush
	lsr	w10, w9, #11
	orr	w10, w23, w10, lsl #24
	ubfx	w11, w9, #3, #8
	and	w12, w9, #7
	orr	w11, w11, w12, lsl #13
	mov	w12, #0x1f00              ; buffer fullness 0x7ff, one raw block
	movk	w12, #0xfc, lsl #16
	orr	w11, w11, w12
	ldr	x0, [sp, #AD_OUT]
	str	w10, [x0]
	str	w11, [x0, #4]             ; its fourth byte is overwritten by the frame
	add	x0, x0, #7
	add	x9, x0, x2
	str	x9, [sp, #AD_OUT]
	mov	x1, x24
	add	x24, x24, x2
	bl	_memcpy
	b	Lad_frame
Lad_flush:
	mov	w0, w19
	mov	x1, x22
	ldr	x2, [sp, #AD_OUT]
	sub	x2, x2, x22
	ldr	x9, [sp, #AD_SENT]
	add	x9, x9, x2
	str	x9, [sp, #AD_SENT]
	bl	send_all
	mov	w24, w0
	mov	x0, x22
	bl	_free
	cbnz	w24, Lad_frag
	mov	w0, #0
	b	Lret4
Lad_ok:
	ldr	x9, [sp, #AD_SENT]
	cmp	x9, #0
	cset	w0, ne
	b	Lret4

; live_stream(fd, url, head) — stream a live broadcast as ADTS: its 5-second segments in order, unwrapped.
	.pushsection __DATA,__data
Llive_head:	.ascii	"HTTP/1.1 200 OK\r\nContent-Type: audio/aac\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
Llive_head_end:
	.popsection
	.equ LS_BUF,	16                ; {data, len}
	.equ LS_HDR,	32                ; struct curl_header *
	.equ LS_URL,	48                ; char[4128]: a media URL and "&sq=N"
	.equ LS_SIZE,	LS_URL + 4128
live_stream:
	FRAME	4, LS_SIZE
	mov	w20, w0
	mov	x21, x1
	mov	w22, w3
	mov	w0, w20
	GADDR	x1, Llive_head
	mov	x2, #(Llive_head_end - Llive_head)
	bl	send_all
	cbz	w0, Lret4
	cbnz	w22, Lret4                ; HEAD: the response head was all it wanted
	bl	curl_new
	mov	x19, x0
	cbz	x0, Lret4
	mov	x23, #0                   ; segment number, 0 until the newest one is known
	mov	w24, #0                   ; failed fetches in a row
Lls_fetch:
	mov	x0, x21
	cbz	x23, Lls_get
	stp	x21, x23, [sp]
	add	x0, sp, #LS_URL
	mov	x1, #4128
	CSTR	x2, "%s&sq=%ld"
	bl	_snprintf
	add	x0, sp, #LS_URL
Lls_get:
	mov	x1, #0
	mov	x2, #0
	add	x3, sp, #LS_BUF
	mov	x4, #API_TIMEOUT_MS       ; a segment not out yet keeps the request waiting
	bl	http
	cbz	w0, Lls_failed
	mov	x0, x19
	bl	status_of
	cmp	x0, #200
	b.ne	Lls_skip                  ; 204: nothing new in time
	cbnz	x23, Lls_send
	mov	x0, x19                   ; the newest segment tells its number
	mov	w25, #1                   ; a missing number ends the stream
	CSTR	x1, "X-Sequence-Num"
	mov	x2, #0
	mov	w3, #CURLH_HEADER
	mov	w4, #-1
	add	x5, sp, #LS_HDR
	bl	_curl_easy_header
	cbnz	w0, Lls_free
	ldr	x9, [sp, #LS_HDR]
	ldr	x0, [x9, #8]
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	subs	x23, x0, #1               ; start one segment back: a cushion for the speaker
	csinc	x23, x23, xzr, gt
	mov	w25, #0
	b	Lls_free
Lls_send:
	mov	w0, w20
	ldp	x1, x2, [sp, #LS_BUF]
	bl	adts_send
	cmp	w0, #0
	cset	w25, eq                   ; the speaker went away, or the stream is not one we can read
	add	x23, x23, #1
	mov	w24, #0
Lls_free:
	ldr	x0, [sp, #LS_BUF]
	bl	_free
	cbz	w25, Lls_fetch
	b	Lls_cleanup
Lls_skip:
	ldr	x0, [sp, #LS_BUF]
	bl	_free
Lls_failed:
	add	w24, w24, #1
	cmp	w24, #LIVE_TRIES
	b.lo	Lls_fetch
Lls_cleanup:
	mov	x0, x19
	bl	_curl_easy_cleanup
	b	Lret4

; handle_conn(fd) — a proxy thread: read one request, serve the stream its token names, close.
	.equ H_RANGE,	16                ; char[256]
	.equ H_REQ,	272               ; char[REQ_MAX]
	.equ H_SIZE,	H_REQ + REQ_MAX
	ENTRY	handle_conn
	FRAME	4, H_SIZE
	mov	w19, w0
	add	x20, sp, #H_REQ
	mov	x21, #0
Lhc_recv:
	mov	x9, #(REQ_MAX - 1)
	cmp	x21, x9
	b.hs	Lhc_parse                 ; full: parse what there is
	mov	w0, w19
	add	x1, x20, x21
	sub	x2, x9, x21
	mov	w3, #0
	bl	_recv
	cmp	x0, #0
	b.le	Lhc_close                 ; closed, error or SO_RCVTIMEO
	add	x21, x21, x0
	strb	wzr, [x20, x21]
	mov	x0, x20
	CSTR	x1, "\r\n\r\n"
	bl	_strstr
	cbz	x0, Lhc_recv
Lhc_parse:
	mov	x0, x20
	mov	w1, #' '
	bl	_strchr                   ; the path follows the method
	CSTR	x1, "400 Bad Request"
	cbz	x0, Lhc_reply
	add	x22, x0, #1
	strb	wzr, [sp, #H_RANGE]
	mov	x0, x20
	CSTR	x1, "\nRange:"
	add	x2, sp, #H_RANGE
	bl	header_value
	mov	x0, x22
	GADDR	x1, Ls_stream
	mov	x2, #8
	bl	_strncmp
	GADDR	x1, Ls_404
	cbnz	w0, Lhc_reply
	add	x22, x22, #8              ; the token
	mov	x23, #0                   ; private copy of the media URL
	LOCK
	BADDR	x21, B_SLOTTOK
	add	x24, x28, #G_SLOTURL
Lhc_find:
	mov	x0, x22
	mov	x1, x21
	mov	x2, #32
	bl	_strncmp
	cbz	w0, Lhc_hit
	add	x21, x21, #TOKEN_STRIDE
	add	x24, x24, #8
	add	x9, x28, #(G_SLOTURL + 8 * SLOTS)
	cmp	x24, x9
	b.lo	Lhc_find
	b	Lhc_unlock
Lhc_hit:
	ldrb	w25, [x21, #(TOKEN_STRIDE - 1)] ; a live broadcast
	ldr	x0, [x24]
	cbz	x0, Lhc_unlock
	bl	_strdup
	mov	x23, x0
Lhc_unlock:
	UNLOCK
	GADDR	x1, Ls_404
	CSTR	x2, "unknown stream"
	cbz	x23, Lhc_reply2
	ldrb	w9, [x20]
	cmp	w9, #'H'
	cset	w3, eq                    ; HEAD: the response head only
	mov	w0, w19
	mov	x1, x23
	add	x2, sp, #H_RANGE
	cbnz	w25, Lhc_live
	ldrb	w9, [x23]
	cmp	w9, #'/'
	b.eq	Lhc_file
	cmp	w9, #'#'
	b.eq	Lhc_text
	mov	x4, x24                   ; its slot, to learn the CDN's redirect
	bl	vod_stream
	b	Lhc_free
Lhc_file:
	bl	file_stream
	b	Lhc_free
Lhc_text:
	mov	w2, w3
	bl	text_stream
	b	Lhc_free
Lhc_live:
	bl	live_stream
Lhc_free:
	mov	x0, x23
	bl	_free
	b	Lhc_close
Lhc_reply:
	GADDR	x2, Ls_slash+1
Lhc_reply2:
	mov	w0, w19
	bl	respond
Lhc_close:
	mov	w0, w19
	bl	_close
	ldr	x0, [x28, #G_CONNS]
	bl	_dispatch_semaphore_signal
	mov	x0, #0
	b	Lret4

; server_run(fd) — accept LAN peers, one detached thread per connection.
	ENTRY	server_run
	FRAME	2, 48
	mov	w19, w0
Lsr_slot:
	ldr	x0, [x28, #G_CONNS]
	mov	x1, #DISPATCH_TIME_FOREVER
	bl	_dispatch_semaphore_wait
Lsr_accept:
	mov	w9, #16
	str	w9, [sp, #32]
	mov	w0, w19
	add	x1, sp, #16
	add	x2, sp, #32
	bl	_accept
	tbz	w0, #31, Lsr_peer
	mov	w0, #ACCEPT_BACKOFF_US    ; e.g. out of descriptors: do not spin
	bl	_usleep
	b	Lsr_accept
Lsr_peer:
	mov	w20, w0
	ldr	w9, [sp, #20]             ; the peer, network order like G_LAN
	ldr	x10, [x28, #G_LAN]        ; one atomic load: address and mask agree
	lsr	x11, x10, #32
	cbz	w11, Lsr_loopback
	eor	w12, w9, w10
	tst	w12, w11
	b.eq	Lsr_ok                    ; same subnet
Lsr_loopback:
	and	w12, w9, #0xff            ; the first octet
	cmp	w12, #127
	b.eq	Lsr_ok                    ; loopback
	mov	w0, w20
	CSTR	x1, "403 Forbidden"
	CSTR	x2, "local network only"
	bl	respond
	mov	w0, w20
	bl	_close
	b	Lsr_accept
Lsr_ok:
	mov	x9, #CLIENT_TIMEOUT_S
	stp	x9, xzr, [sp]             ; struct timeval
	mov	w0, w20
	mov	w1, #SOL_SOCKET
	mov	w2, #SO_RCVTIMEO          ; a silent client cannot pin a thread
	mov	x3, sp
	mov	w4, #16
	bl	_setsockopt
	add	x0, sp, #40
	mov	x1, #0
	adr	x2, handle_conn
	mov	x3, x20
	bl	_pthread_create
	cbnz	w0, Lsr_drop
	ldr	x0, [sp, #40]
	bl	_pthread_detach
	b	Lsr_slot
Lsr_drop:
	mov	w0, w20
	bl	_close
	b	Lsr_accept

; server_start() — listen on an OS-assigned port and start the accept thread; w0 = 1 if listening.
server_start:
	FRAME	1, 48
	mov	x0, #MAX_CONNS
	bl	_dispatch_semaphore_create
	str	x0, [x28, #G_CONNS]
	mov	w0, #AF_INET
	mov	w1, #SOCK_STREAM
	mov	w2, #0
	bl	_socket
	mov	w19, w0
	tbnz	w0, #31, Lss_fail
	mov	w1, #64
	bl	_listen                   ; on any address and a port the system picks
	cbnz	w0, Lss_close
	mov	w9, #16
	str	w9, [sp, #32]
	mov	w0, w19
	add	x1, sp, #16
	add	x2, sp, #32
	bl	_getsockname
	cbnz	w0, Lss_close
	ldrh	w9, [sp, #18]
	rev16	w9, w9
	str	w9, [x28, #G_PORT]
	add	x0, sp, #40
	mov	x1, #0
	adr	x2, server_run
	mov	x3, x19
	bl	_pthread_create
	cbnz	w0, Lss_close
	ldr	x0, [sp, #40]
	bl	_pthread_detach
	mov	w0, #1
	b	Lret1
Lss_close:
	mov	w0, w19
	bl	_close
Lss_fail:
	mov	w0, #0
	b	Lret1

; ---- Resolver: a link or search text -> media URL and metadata (worker queue) ----

; is_link(text) — w0 = 1 for a link (no spaces, with a '.' and a '/'), 0 for search words.
is_link:
	mov	w1, #0                    ; bit 0: a '.', bit 1: a '/'
Lil_next:
	ldrb	w2, [x0], #1
	cmp	w2, #' '
	b.eq	Lil_no
	cbz	w2, Lil_end
	cmp	w2, #'.'
	cset	w3, eq
	orr	w1, w1, w3
	cmp	w2, #'/'
	cset	w3, eq
	orr	w1, w1, w3, lsl #1
	b	Lil_next
Lil_end:
	cmp	w1, #3
	cset	w0, eq
	ret
Lil_no:
	mov	w0, #0
	ret

; video_id(link, out[12]) -> the 11-character id after "v=", "/shorts/", "/embed/", "/live/" or "youtu.be/" (copied to out), else the link.
	.pushsection __DATA,__data
Lid_keys:	.asciz	"v="
	.asciz	"/shorts/"
	.asciz	"/embed/"
	.asciz	"/live/"
	.asciz	"youtu.be/"
	.byte	0
	.popsection
video_id:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	GADDR	x21, Lid_keys
Lvi_key:
	ldrb	w9, [x21]
	cbz	w9, Lvi_self
	mov	x0, x21
	bl	_strlen
	mov	x23, x0
	mov	x0, x19
	mov	x1, x21
	bl	_strstr
	add	x21, x21, x23
	add	x21, x21, #1              ; the next key
	cbz	x0, Lvi_key
	add	x22, x0, x23              ; past the key
	mov	x0, x22
	CSTR	x1, "&?/#"
	bl	_strcspn
	cmp	x0, #11
	b.lo	Lvi_key
	mov	x0, x20
	mov	x1, x22
	mov	x2, #12
	bl	_strlcpy
	mov	x0, x20
	b	Lret3
Lvi_self:
	mov	x0, x19
	b	Lret3

; jfind(json, key) -> the value after the first key (written with its quotes and colon), or NULL.
jfind:
	FRAME	1
	mov	x19, x1
	cbz	x0, Lret1
	bl	_strstr
	cbz	x0, Lret1
	mov	x20, x0
	mov	x0, x19
	bl	_strlen
	add	x0, x20, x0
	b	Lret1

; jstr(value, out, cap) — decode the JSON string at value into out; "" when it is not one.
jstr:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	strb	wzr, [x20]
	cbz	x19, Lret2
	ldrb	w9, [x19]
	cmp	w9, #'"'
	b.ne	Lret2
	add	x9, x19, #1
Ljs_scan:
	ldrb	w10, [x9], #1
	cbz	w10, Lret2                ; unterminated
	cmp	w10, #'\\'
	b.ne	Ljs_quote
	ldrb	w10, [x9], #1
	cbz	w10, Lret2
	b	Ljs_scan
Ljs_quote:
	cmp	w10, #'"'
	b.ne	Ljs_scan
	CLASS	x0, NSData
	mov	x2, x19
	sub	x3, x9, x19               ; the literal with both quotes
	mov	w4, #0
	SEND	S_dataWithBytesNoCopy_length_freeWhenDone_
	mov	x2, x0
	CLASS	x0, NSJSONSerialization
	mov	x3, #4                    ; NSJSONReadingFragmentsAllowed
	mov	x4, #0
	SEND	S_JSONObjectWithData_options_error_
	SEND	S_UTF8String
	cbz	x0, Lret2
	mov	x1, x0
	mov	x0, x20
	mov	x2, x21
	bl	_strlcpy
	b	Lret2

; jesc(out[1024], text) — text escaped for a JSON string; control characters become spaces.
jesc:
	add	x9, x0, #1016
Lje_next:
	ldrb	w10, [x1], #1
	cbz	w10, Lje_end
	cmp	x0, x9
	b.hs	Lje_end
	cmp	w10, #' '
	b.hs	Lje_char
	mov	w10, #' '
Lje_char:
	cmp	w10, #'"'
	b.eq	Lje_esc
	cmp	w10, #'\\'
	b.ne	Lje_put
Lje_esc:
	mov	w11, #'\\'
	strb	w11, [x0], #1
Lje_put:
	strb	w10, [x0], #1
	b	Lje_next
Lje_end:
	strb	wzr, [x0]
	ret

; hdrs(list, packed) -> list with each string of a packed list appended (an empty string ends it); x1 = what follows.
hdrs:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
Lhs_next:
	ldrb	w9, [x20]
	cbz	w9, Lhs_end
	mov	x0, x19
	mov	x1, x20
	bl	_curl_slist_append
	mov	x19, x0
	mov	x0, x20
	bl	nextstr
	mov	x20, x0
	b	Lhs_next
Lhs_end:
	mov	x0, x19
	add	x1, x20, #1
	b	Lret2

; resolve_file(job) -> PLAY_OK: a file on this Mac, by path or file URL; its name is the title.
resolve_file:
	FRAME	2
	mov	x19, x0
	mov	w9, #KIND_FILE
	str	w9, [x19, #JOB_KIND]
	ldr	x20, [x19, #JOB_QUERY]
	ldrb	w9, [x20]
	cmp	w9, #'/'
	b.eq	Lrf_path
	mov	x0, x20                   ; a file URL: its path becomes the query
	bl	mkurl
	SEND	S_path
	SEND	S_UTF8String
	cbz	x0, Lrf_path
	bl	_strdup
	cbz	x0, Lrf_path
	mov	x21, x0
	mov	x0, x20
	bl	_free
	str	x21, [x19, #JOB_QUERY]
	mov	x20, x21
Lrf_path:
	mov	x0, x20
	bl	mkstr
	mov	x2, x0
	CLASS	x0, NSURL
	SEND	S_fileURLWithPath_
	mov	x21, x0
	SEND	S_absoluteString
	SEND	S_UTF8String
	mov	x1, x0
	add	x0, x19, #JOB_URL
	mov	x2, #4096
	bl	_strlcpy
	mov	x0, x21
	mov	x1, x19
	bl	url_title
	b	Lret2

; resolve_web(job) -> PLAY_OK for any other web address (https when it has no scheme), played as it is; PLAY_FAILED if it is not one.
resolve_web:
	FRAME	2, 16
	mov	x19, x0
	mov	w9, #KIND_WEB
	str	w9, [x19, #JOB_KIND]
	ldr	x20, [x19, #JOB_QUERY]
	mov	x0, x20
	GADDR	x1, Ls_sep
	bl	_strstr
	CSTR	x9, "https://"
	GADDR	x10, Ls_slash+1
	cmp	x0, #0
	csel	x9, x10, x9, ne
	stp	x9, x20, [sp]
	add	x0, x19, #JOB_URL
	mov	x1, #4096
	CSTR	x2, "%s%s"
	bl	_snprintf
	add	x0, x19, #JOB_URL
	bl	mkurl
	cbz	x0, Lrw_bad
	mov	x20, x0
	SEND	S_host                    ; the site, where an artist would be
	SEND	S_UTF8String
	cbz	x0, Lrw_title
	mov	x1, x0
	add	x0, x19, #(JOB_TRACK + T_ARTIST)
	mov	x2, #256
	bl	_strlcpy
Lrw_title:
	mov	x0, x20
	mov	x1, x19
	bl	url_title
	b	Lret2
Lrw_bad:
	CSTR	x9, "this is not a web address"
	str	x9, [x19, #JOB_ERR]
	mov	w0, #PLAY_FAILED
	b	Lret2

; url_title(url, job) -> PLAY_OK, with the URL's last path component, without its extension, as the job's title.
url_title:
	FRAME	1
	mov	x19, x1
	SEND	S_URLByDeletingPathExtension
	SEND	S_lastPathComponent
	SEND	S_UTF8String
	cbz	x0, Lut_ok
	mov	x1, x0
	add	x0, x19, #(JOB_TRACK + T_TITLE)
	mov	x2, #512
	bl	_strlcpy
Lut_ok:
	mov	w0, #PLAY_OK
	b	Lret1

; resolve's frame, which api fills.
	.equ RS_BUF,	16                ; {data, len}
	.equ RS_VIS,	32                ; char[288], the visitorData member, or ""
	.equ RS_ID,	320               ; char[16]
	.equ RS_ESC,	336               ; char[1024]
	.equ RS_TAIL,	1360              ; char[1280], the request after its context
	.equ RS_CPN,	2640              ; char[32]
	.equ RS_SIZE,	2672

; api(endpoint, client, tail, frame) — POST to InnerTube as a client on the handle in x19, into resolve's RS_BUF; w0 = 1 on success.
	.equ AP_BODY,	32
	.equ AP_LIST,	40
api:
	FRAME	4, 48
	mov	x21, x0
	mov	x20, x1
	mov	x22, x2
	add	x23, x3, #RS_BUF
	add	x24, x3, #RS_VIS
	mov	x0, x20
	bl	nextstr
	mov	x25, x0                   ; context fields
	bl	nextstr
	mov	x26, x0                   ; the client's headers
	mov	x0, #0
	ADDR	x1, Lapi_headers
	bl	hdrs
	mov	x1, x26
	bl	hdrs
	mov	x26, x0
	mov	x0, x21
	bl	nextstr                   ; the field mask
	mov	x1, x0
	mov	x0, x26
	bl	_curl_slist_append
	str	x0, [sp, #AP_LIST]
	mov	x2, x20
	mov	w1, #CURLOPT_USERAGENT
	bl	copt
	stp	x25, x20, [sp]
	stp	x24, x22, [sp, #16]
	add	x0, sp, #AP_BODY
	CSTR	x1, "{\"context\":{\"client\":{%s\"hl\":\"en\",\"gl\":\"US\",\"userAgent\":\"%s\"%s}}%s"
	bl	_asprintf
	mov	w22, #0
	ldr	x9, [sp, #AP_BODY]
	cbz	x9, Lapi_free
	mov	w26, #2                   ; attempts: a kept-alive connection may have been dropped
Lapi_try:
	mov	x0, x21
	ldr	x1, [sp, #AP_BODY]
	ldr	x2, [sp, #AP_LIST]
	mov	x3, x23
	mov	x4, #API_TIMEOUT_MS
	bl	http
	mov	w22, w0
	cbnz	w0, Lapi_free
	subs	w26, w26, #1
	b.ne	Lapi_try
Lapi_free:
	ldr	x0, [sp, #AP_BODY]
	bl	_free
	ldr	x0, [sp, #AP_LIST]
	bl	_curl_slist_free_all
	mov	w0, w22
	b	Lret4

; within(needle) — the needle in parse_player's current format [x21, x25), or NULL.
within:
	stp	x29, x30, [sp, #-16]!
	mov	x1, x0
	mov	x0, x21
	bl	_strstr
	ldp	x29, x30, [sp], #16
	cmp	x0, x25
	csel	x0, x0, xzr, lo
	ret

; jnum(json, key) -> the number after key, quoted or not (0 if absent).
jnum:
	FRAME	0
	bl	jfind
	cbz	x0, Lret0
	ldrb	w9, [x0]
	cmp	w9, #'"'
	cinc	x0, x0, eq
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	b	Lret0

; fmt_info(start, end, fmt) — a format's init and index byte ranges, bitrate and codecs, from its JSON [start, end).
	.pushsection __DATA,__data
Lk_start:	.asciz	"\"start\":"
Lk_end:	.asciz	"\"end\":"
	.popsection
fmt_info:
	FRAME	4
	mov	x21, x0
	mov	x25, x1
	mov	x19, x2
	CSTR	x0, "\"initRange\":"
	bl	within
	cbz	x0, Lfi_rate
	GADDR	x1, Lk_end
	bl	jnum
	str	x0, [x19, #FMT_INIT]
	CSTR	x0, "\"indexRange\":"
	bl	within
	cbz	x0, Lfi_rate
	mov	x20, x0
	GADDR	x1, Lk_start
	bl	jnum
	str	x0, [x19, #FMT_IDX0]
	mov	x0, x20
	GADDR	x1, Lk_end
	bl	jnum
	str	x0, [x19, #FMT_IDX1]
Lfi_rate:
	CSTR	x0, "\"bitrate\":"
	bl	within
	cbz	x0, Lfi_codecs
	add	x0, x0, #10
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	str	x0, [x19, #FMT_RATE]
Lfi_codecs:
	CSTR	x0, "codecs=\\\""            ; in the JSON text: codecs=\"...\"
	bl	within
	cbz	x0, Lret4
	add	x20, x0, #9
	mov	x0, x20
	mov	w1, #92                   ; backslash
	bl	_strchr
	cbz	x0, Lret4
	sub	x2, x0, x20
	cmp	x2, #63
	b.hs	Lret4
	add	x0, x19, #FMT_CODECS
	mov	x1, x20
	add	x2, x2, #1
	bl	_strlcpy
	b	Lret4

; parse_player(job, response) — the best AAC stream, then title, channel, length and live flag; w0 = 1 if there is a stream.
	.pushsection __DATA,__data
Lk_itag:	.asciz	"\"itag\":"
	.popsection
parse_player:
	FRAME	4, 64                     ; the best picture's "url" value and score, its JSON span, the sound's span, then the best muxed stream
	mov	x19, x0
	mov	x20, x1
	stp	xzr, xzr, [sp]
	stp	xzr, xzr, [sp, #16]
	stp	xzr, xzr, [sp, #32]
	stp	xzr, xzr, [sp, #48]
	mov	x0, x1
	CSTR	x1, "\"streamingData\":"
	bl	_strstr
	cbz	x0, Lpp_no
	mov	x21, x0
	mov	x22, #0                   ; the best format's "url" value
	mov	w23, #-1                  ; and its score
Lpp_fmt:
	mov	x0, x21
	GADDR	x1, Lk_itag
	bl	jfind
	cbz	x0, Lpp_picked
	mov	x21, x0
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	mov	x24, x0
	mov	x0, x21
	GADDR	x1, Lk_itag
	bl	_strstr
	mov	x25, x0                   ; the next format starts here
	cbnz	x0, Lpp_one
	mov	x0, x21                   ; the last one ends where videoDetails starts
	CSTR	x1, "\"videoDetails\":"
	bl	_strstr
	mov	x25, x0
Lpp_one:
	CSTR	x0, "\"url\":"
	bl	within
	cbz	x0, Lpp_fmt               ; no plain URL (a cipher or SABR)
	add	x26, x0, #6
	CSTR	x0, "mp4a"
	bl	within
	cbz	x0, Lpp_video             ; not AAC: not every speaker plays it
	CSTR	x0, "\"video/mp4"
	bl	within
	cbz	x0, Lpp_sound
	CSTR	x0, "\"height\":"         ; picture and sound in one: the tallest, for TVs
	bl	within
	cbz	x0, Lpp_fmt
	add	x0, x0, #9
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	ldr	x9, [sp, #56]
	cmp	x0, x9
	b.le	Lpp_fmt
	stp	x26, x0, [sp, #48]
	b	Lpp_fmt
Lpp_sound:
	cmp	x24, #140                 ; score: itag 140 4, audio only 2, no loudness compression 1
	cset	w24, eq
	lsl	w24, w24, #2
	CSTR	x0, "\"audio/"
	bl	within
	cbz	x0, Lpp_drc
	add	w24, w24, #2
Lpp_drc:
	CSTR	x0, "\"isDrc\":true"
	bl	within
	cbnz	x0, Lpp_score
	add	w24, w24, #1
Lpp_score:
	cmp	w24, w23
	b.le	Lpp_fmt
	mov	w23, w24
	mov	x22, x26
	stp	x21, x25, [sp, #32]
	b	Lpp_fmt
Lpp_video:
	CSTR	x0, "\"video/mp4"         ; a picture: MP4, SDR, H.264 (or AV1 where it decodes in hardware)
	bl	within
	cbz	x0, Lpp_fmt
	CSTR	x0, "HDR"
	bl	within
	cbnz	x0, Lpp_fmt
	mov	x24, #0
	CSTR	x0, "avc1"
	bl	within
	cbnz	x0, Lpp_height
	ldr	w9, [x28, #G_AV1]
	ldr	w10, [x28, #G_TV]
	bic	w9, w9, w10               ; (any TV flag clears it)
	cbz	w9, Lpp_fmt
	CSTR	x0, "av01"
	bl	within
	cbz	x0, Lpp_fmt
	mov	x24, #1                   ; AV1: the same picture in fewer bytes
Lpp_height:
	CSTR	x0, "\"height\":"
	bl	within
	cbz	x0, Lpp_fmt
	add	x0, x0, #9
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	cmp	x0, #VIDEO_MAX_H
	b.gt	Lpp_fmt
	add	x24, x24, x0, lsl #2      ; score: height, then 60 fps, then the codec
	CSTR	x0, "\"fps\":"
	bl	within
	cbz	x0, Lpp_vscore
	add	x0, x0, #6
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	cmp	x0, #30
	cset	x9, gt
	add	x24, x24, x9, lsl #1
Lpp_vscore:
	ldr	x9, [sp, #8]
	cmp	x24, x9
	b.le	Lpp_fmt
	stp	x26, x24, [sp]
	stp	x21, x25, [sp, #16]
	b	Lpp_fmt
Lpp_picked:
	ldp	x0, x1, [sp, #32]
	add	x2, x19, #JOB_AFMT
	cbz	x0, 1f
	bl	fmt_info
1:	ldp	x0, x1, [sp, #16]
	add	x2, x19, #JOB_VFMT
	cbz	x0, 1f
	bl	fmt_info
1:	ldr	x0, [sp]
	ADDO	x1, x19, JOB_VURL
	mov	x2, #4096
	bl	jstr
	ldr	x0, [sp, #48]
	ADDO	x1, x19, JOB_MURL
	mov	x2, #4096
	bl	jstr
	mov	x0, x22
	add	x1, x19, #JOB_URL
	mov	x2, #4096
	bl	jstr
	add	x0, x19, #JOB_URL
	CSTR	x1, "http"
	mov	x2, #4
	bl	_strncmp
	cbnz	w0, Lpp_no                ; only a web URL is ever played
	mov	x0, x20
	CSTR	x1, "\"title\":"
	bl	jfind
	add	x1, x19, #(JOB_TRACK + T_TITLE)
	mov	x2, #512
	bl	jstr
	mov	x0, x20
	CSTR	x1, "\"author\":"
	bl	jfind
	add	x1, x19, #(JOB_TRACK + T_ARTIST)
	mov	x2, #256
	bl	jstr
	mov	x0, x20                   ; artwork: the largest JPEG thumbnail YouTube lists (they grow along the list)
	CSTR	x1, "\"thumbnails\":["
	bl	jfind
	cbz	x0, Lpp_thumbed
	mov	x21, x0
	mov	w1, #']'
	bl	_strchr
	cbz	x0, Lpp_thumbed
	mov	x25, x0
	mov	x22, #0
Lpp_thumb:
	mov	x0, x21
	CSTR	x1, "\"url\":"
	bl	_strstr
	cbz	x0, Lpp_tpick
	cmp	x0, x25
	b.hs	Lpp_tpick
	add	x21, x0, #1
	add	x24, x0, #6
	mov	x0, x24
	CSTR	x1, "\"https://i.ytimg.com/vi_webp"
	mov	x2, #28
	bl	_strncmp
	cbz	w0, Lpp_thumb             ; WebP: not every speaker shows it
	mov	x22, x24
	b	Lpp_thumb
Lpp_tpick:
	mov	x0, x22
	add	x1, x19, #(JOB_TRACK + T_ART)
	mov	x2, #2048
	bl	jstr
Lpp_thumbed:
	mov	x0, x20
	CSTR	x1, "\"lengthSeconds\":\""
	bl	jfind
	cbz	x0, Lpp_live
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	str	x0, [x19, #JOB_DUR]
Lpp_live:
	mov	x0, x20
	CSTR	x1, "\"isLive\":true"
	bl	_strstr
	cmp	x0, #0
	cset	w9, ne
	str	w9, [x19, #JOB_LIVE]
	cbz	w9, Lpp_yes
	str	xzr, [x19, #JOB_DUR]      ; a live broadcast has no length
	mov	x0, x20                   ; its picture: YouTube's own HLS, when offered
	CSTR	x1, "\"hlsManifestUrl\":"
	bl	jfind
	ADDO	x1, x19, JOB_VURL
	mov	x2, #4096
	bl	jstr
Lpp_yes:
	mov	w0, #1
	b	Lret4
Lpp_no:
	mov	x0, x20                   ; YouTube's reason, e.g. a bot check
	CSTR	x1, "\"reason\":"
	bl	jfind
	add	x1, x19, #JOB_MSG
	mov	x2, #128
	bl	jstr
	mov	w0, #0
	b	Lret4

; resolve(job) -> PLAY_OK with the job's stream and track filled, or PLAY_FAILED (JOB_ERR says why, when known).
resolve:
	FRAME	4, RS_SIZE
	mov	x20, x0
	bl	_objc_autoreleasePoolPush
	mov	x26, x0
	ldr	x22, [x20, #JOB_QUERY]    ; a file or another site needs no lookup
	ldrb	w9, [x22]
	cmp	w9, #'/'
	b.eq	Lrs_file
	mov	x0, x22
	CSTR	x1, "file://"
	mov	x2, #7
	bl	_strncmp
	cbz	w0, Lrs_file
	mov	x0, x22
	bl	is_link
	cbz	w0, Lrs_tube              ; search words
	mov	x0, x22
	CSTR	x1, "youtu"
	bl	_strstr
	cbnz	x0, Lrs_tube
	mov	x0, x20                   ; any other address plays as it is
	bl	resolve_web
	b	Lrs_named
Lrs_file:
	mov	x0, x20
	bl	resolve_file
Lrs_named:
	mov	w21, w0
	b	Lrs_pool
Lrs_tube:
	mov	w21, #PLAY_FAILED
	bl	curl_new
	mov	x19, x0
	cbz	x0, Lrs_pool
	mov	x2, #CURL_HTTP_VERSION_1_1
	mov	w1, #CURLOPT_HTTP_VERSION
	bl	copt
	GADDR	x2, Ls_slash+1             ; every encoding curl decodes
	mov	w1, #CURLOPT_ACCEPT_ENCODING
	bl	copt
	mov	x2, #API_CONNECT_MS
	mov	w1, #CURLOPT_CONNECTTIMEOUT_MS
	bl	copt
	add	x0, sp, #RS_VIS           ; a visitorData first, as the WEB client, once per launch
	BADDR	x1, B_VISITOR
	mov	x2, #288
	bl	_strlcpy
	ldrb	w9, [sp, #RS_VIS]
	cbnz	w9, Lrs_id
	ADDR	x0, Lep_guide
	ADDR	x1, Lc_web
	CSTR	x2, "}"
	mov	x3, sp
	bl	api
	cbz	w0, Lrs_id
	ldr	x0, [sp, #RS_BUF]
	CSTR	x1, "\"visitorData\":\""
	bl	jfind                     ; its JSON text goes into our requests as it is
	cbz	x0, Lrs_vfree
	mov	x22, x0
	CSTR	x1, "\""
	bl	_strcspn
	cbz	x0, Lrs_vfree
	stp	x0, x22, [sp]
	add	x0, sp, #RS_VIS
	mov	x1, #288
	CSTR	x2, ",\"visitorData\":\"%.*s\""
	bl	_snprintf
	BADDR	x0, B_VISITOR
	add	x1, sp, #RS_VIS
	mov	x2, #288
	bl	_strlcpy
Lrs_vfree:
	ldr	x0, [sp, #RS_BUF]
	bl	_free
Lrs_id:
	ldr	x22, [x20, #JOB_QUERY]
	mov	x0, x22
	bl	is_link
	cbz	w0, Lrs_search
	mov	x0, x22
	add	x1, sp, #RS_ID
	bl	video_id
	mov	x22, x0
	b	Lrs_player
Lrs_search:
	add	x0, sp, #RS_ESC           ; the top video result, as the ANDROID client
	mov	x1, x22
	bl	jesc
	add	x9, sp, #RS_ESC
	str	x9, [sp]
	add	x0, sp, #RS_TAIL
	mov	x1, #1280
	CSTR	x2, ",\"query\":\"%s\",\"params\":\"EgIQAfABAQ==\"}"
	bl	_snprintf
	ADDR	x0, Lep_search
	ADDR	x1, Lc_android
	add	x2, sp, #RS_TAIL
	mov	x3, sp
	bl	api
	cbz	w0, Lrs_done
	ldr	x0, [sp, #RS_BUF]
	CSTR	x1, "\"compactVideoRenderer\":"
	bl	jfind
	CSTR	x1, "\"videoId\":"
	bl	jfind
	add	x1, sp, #RS_ID
	mov	x2, #16
	bl	jstr
	ldr	x0, [sp, #RS_BUF]
	bl	_free
	add	x22, sp, #RS_ID
	ldrb	w9, [x22]
	cbz	w9, Lrs_done              ; no results
Lrs_player:
	add	x0, sp, #RS_ESC
	mov	x1, x22
	bl	jesc
	add	x23, sp, #RS_CPN          ; a random client playback nonce
	mov	w24, #16
Lrs_cpn:
	mov	w0, #64
	bl	_arc4random_uniform
	CSTR	x9, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
	ldrb	w9, [x9, w0, uxtw]
	strb	w9, [x23], #1
	subs	w24, w24, #1
	b.ne	Lrs_cpn
	strb	wzr, [x23]
	add	x9, sp, #RS_ESC
	add	x10, sp, #RS_CPN
	stp	x9, x10, [sp]
	add	x0, sp, #RS_TAIL
	mov	x1, #1280
	CSTR	x2, ",\"videoId\":\"%s\",\"contentCheckOk\":true,\"racyCheckOk\":true,\"playbackContext\":{\"contentPlaybackContext\":{\"html5Preference\":\"HTML5_PREF_WANTS\"}},\"cpn\":\"%s\"}"
	bl	_snprintf
	ADDR	x23, Lclients
Lrs_client:
	ldrh	w24, [x23]
	cbz	w24, Lrs_none
	ADDR	x0, Lep_player
	add	x1, x23, #2
	add	x2, sp, #RS_TAIL
	mov	x3, sp
	bl	api
	add	x23, x23, x24
	cbz	w0, Lrs_client
	mov	x0, x20
	ldr	x1, [sp, #RS_BUF]
	bl	parse_player
	mov	w25, w0
	ldr	x0, [sp, #RS_BUF]
	bl	_free
	cbz	w25, Lrs_client           ; the next client may cover what this one refused
	ldrb	w9, [x20, #(JOB_TRACK + T_ART)]
	cbnz	w9, Lrs_ok
	str	x22, [sp]                 ; no thumbnail listed: this one always exists
	add	x0, x20, #(JOB_TRACK + T_ART)
	mov	x1, #2048
	CSTR	x2, "https://i.ytimg.com/vi/%s/hqdefault.jpg"
	bl	_snprintf
Lrs_ok:
	mov	w21, #PLAY_OK
	b	Lrs_done
Lrs_none:
	add	x0, x20, #JOB_MSG
	str	x0, [x20, #JOB_ERR]
	ldrb	w9, [x0]
	cbnz	w9, Lrs_done              ; the reason YouTube gave
	str	x22, [sp]
	mov	x1, #128
	CSTR	x2, "no playable formats for %s"
	bl	_snprintf
Lrs_done:
	mov	x0, x19
	bl	_curl_easy_cleanup
Lrs_pool:
	mov	x0, x26
	bl	_objc_autoreleasePoolPop
	mov	w0, w21
	b	Lret4

; ---- User interface (main thread) ----

; mkstr(cstr) -> an autoreleased NSString.
mkstr:
	mov	x2, x0
	CLASS	x0, NSString
	SENDT	S_stringWithUTF8String_

; setstr(control, cstr) — control.stringValue = cstr.
setstr:
	FRAME	1
	mov	x19, x0
	mov	x0, x1
	bl	mkstr
	mov	x2, x0
	mov	x0, x19
	SEND	S_setStringValue_
	b	Lret1

; symbol(name, description) -> an SF Symbol image.
symbol:
	FRAME	1
	mov	x19, x1
	bl	mkstr
	mov	x20, x0
	mov	x0, x19
	bl	mkstr
	mov	x3, x0                    ; accessibility description (VoiceOver)
	mov	x2, x20
	CLASS	x0, NSImage
	SEND	S_imageWithSystemSymbolName_accessibilityDescription_
	b	Lret1

; frame_rect(x0, rect) — d0-d3 = the NSRect of a packed top-left rect; x0 is kept.
frame_rect:
	ubfx	x9, x1, #48, #16
	ubfx	x10, x1, #16, #16
	mov	w11, #WIN_H
	sub	w11, w11, w10
	sub	w11, w11, w9              ; y = WIN_H - top - height
	and	x10, x1, #0xffff
	scvtf	d0, w10
	scvtf	d1, w11
	ubfx	x10, x1, #32, #16
	scvtf	d2, w10
	scvtf	d3, w9
	ret

; ui_run(program) — run a UI program (written with the OP_END STO LD ADDV CLS CALL MSG macros, argument kinds in Lk_table).
	.equ VM_INT,	0                 ; x0-x7
	.equ VM_DBL,	64                ; d0-d5
	.equ VM_SIZE,	112
ui_run:
	FRAME	4, VM_SIZE
	mov	x19, x0
Lvm_op:
	ldrb	w9, [x19], #1
	cbz	w9, Lret4
	cmp	w9, #3
	b.hi	Lvm_reg
	b.eq	Lvm_add
	ldrb	w10, [x19], #1
	add	x10, x28, x10, lsl #3
	cmp	w9, #1
	b.ne	Lvm_load
	str	x20, [x10]
	b	Lvm_op
Lvm_load:
	ldr	x20, [x10]
	b	Lvm_op
Lvm_add:
	ldr	x0, [x28, #G_CONTENT]
	mov	x2, x20
	SEND	S_addSubview_
	b	Lvm_op
Lvm_reg:
	ldrb	w10, [x19], #1            ; an index
	cmp	w9, #5
	b.hi	Lvm_msg
	add	x11, x27, #B_REG
	ldr	x24, [x11, x10, lsl #3]   ; 4: a class, 5: a function
	b.eq	Lvm_call
	mov	x20, x24
	b	Lvm_op
Lvm_call:
	mov	x22, #0                   ; its arguments start at x0
	b	Lvm_args
Lvm_msg:
	BADDR	x11, B_SEL
	ldr	x1, [x11, x10, lsl #3]
	stp	x20, x1, [sp, #VM_INT]    ; receiver, selector
	ldr	x24, [x27, #F_objc_msgSend]
	mov	x22, #2
Lvm_args:
	ldrb	w26, [x19]                ; '=': the result becomes current
	mov	x21, x19                  ; kinds
	mov	x0, x19
	bl	nextstr
	mov	x19, x0                   ; arguments
	mov	x23, #0
Lvm_kind:
	ldrb	w9, [x21], #1
	cbz	w9, Lvm_send
	adr	x10, Lk_table - '='
	ldrb	w10, [x10, x9]
	adr	x11, Lk_base
	add	x11, x11, x10, lsl #2
	br	x11
Lk_base:
Lk_skip:
	b	Lvm_kind                  ; '='
Lk_ext:
	ldrb	w10, [x19], #1            ; an extern double
	add	x11, x27, #B_REG
	ldr	x11, [x11, x10, lsl #3]
	ldr	d0, [x11]
	b	Lvm_d
Lk_rect:
	ldr	x1, [x19], #8
	bl	frame_rect
	b	Lk_rect4
Lk_raw:
	ldr	x9, [x19], #8             ; x, y, width, height from the bottom-left
	sxth	w10, w9
	scvtf	d0, w10
	asr	x10, x9, #16
	sxth	w10, w10
	scvtf	d1, w10
	asr	x10, x9, #32
	sxth	w10, w10
	scvtf	d2, w10
	asr	x10, x9, #48
	scvtf	d3, w10
Lk_rect4:
	stp	d0, d1, [sp, #VM_DBL]
	stp	d2, d3, [sp, #(VM_DBL + 16)]
	mov	x23, #4
	b	Lvm_kind
Lk_unit:
	ldrb	w9, [x19], #1             ; a color channel: n / 255
	ucvtf	d0, w9
	mov	w9, #255
	ucvtf	d1, w9
	fdiv	d0, d0, d1
	b	Lvm_d
Lk_dbl:
	ldrh	w9, [x19], #2
	ucvtf	d0, w9
	fmov	d1, #0.25
	fmul	d0, d0, d1
Lvm_d:
	add	x9, sp, #VM_DBL
	str	d0, [x9, x23, lsl #3]
	add	x23, x23, #1
	b	Lvm_kind
Lk_byte:
	ldrb	w0, [x19], #1
	b	Lvm_i
Lk_word:
	ldr	w0, [x19], #4
	b	Lvm_i
Lk_quad:
	add	x19, x19, #7
	and	x19, x19, #~7
	ldr	x0, [x19], #8
	b	Lvm_i
Lk_buf:
	ldrh	w9, [x19], #2
	add	x0, x27, x9
	b	Lvm_i
Lk_cur:
	mov	x0, x20
	b	Lvm_i
Lk_slot:
	ldrb	w9, [x19], #1
	ldr	x0, [x28, x9, lsl #3]
	b	Lvm_i
Lk_cstr:
	mov	x0, x19
	b	Lvm_s
Lk_str:
	mov	x0, x19
	bl	mkstr
	b	Lvm_s
Lk_sel:
	mov	x0, x19
	bl	_sel_registerName
Lvm_s:
	mov	x25, x0
	mov	x0, x19
	bl	nextstr
	mov	x19, x0
	mov	x0, x25
Lvm_i:
	str	x0, [sp, x22, lsl #3]
	add	x22, x22, #1
	b	Lvm_kind
Lvm_send:
	ldp	x0, x1, [sp, #VM_INT]
	ldp	x2, x3, [sp, #(VM_INT + 16)]
	ldp	x4, x5, [sp, #(VM_INT + 32)]
	ldp	x6, x7, [sp, #(VM_INT + 48)]
	ldp	d0, d1, [sp, #VM_DBL]
	ldp	d2, d3, [sp, #(VM_DBL + 16)]
	ldp	d4, d5, [sp, #(VM_DBL + 32)]
	blr	x24
	cmp	w26, #'='
	csel	x20, x0, x20, eq
	b	Lvm_op
; Lk_table — the handler of each kind from '=' to 'X', in instructions after Lk_base.
.macro KIND handler
	.byte	(\handler - Lk_base) >> 2
.endm
Lk_table:
	KIND	Lk_skip                   ; =
	KIND	Lk_skip
	KIND	Lk_skip
	KIND	Lk_skip
	KIND	Lk_skip                   ; A
	KIND	Lk_buf                    ; B
	KIND	Lk_cstr                   ; C
	KIND	Lk_dbl                    ; D
	KIND	Lk_skip
	KIND	Lk_ext                    ; F
	KIND	Lk_skip
	KIND	Lk_skip
	KIND	Lk_byte                   ; I
	KIND	Lk_skip
	KIND	Lk_unit                   ; K
	KIND	Lk_sel                    ; L
	KIND	Lk_skip
	KIND	Lk_raw                    ; N
	KIND	Lk_slot                   ; O
	KIND	Lk_skip
	KIND	Lk_quad                   ; Q
	KIND	Lk_rect                   ; R
	KIND	Lk_str                    ; S
	KIND	Lk_skip
	KIND	Lk_skip
	KIND	Lk_cur                    ; V
	KIND	Lk_skip
	KIND	Lk_word                   ; X
	.p2align 2

; ---- Rendering ----

; cache_update(cache, text, cap) — w0 = 1, and copy, if text changed.
cache_update:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	bl	_strcmp
	cbz	w0, Lret2
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	bl	_strlcpy
	mov	w0, #1
	b	Lret2

; show_track(title, artist) — the track in the bar and as the window's title (Window menu, Mission Control), when it changed.
show_track:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	BADDR	x0, B_UITITLE
	mov	x1, x19
	mov	x2, #512
	bl	cache_update
	mov	w21, w0
	BADDR	x0, B_UIARTIST
	mov	x1, x20
	mov	x2, #256
	bl	cache_update
	orr	w0, w0, w21
	cbz	w0, Lret3
	mov	x22, x19
	ldr	x23, [x28, #G_TEXT]
	ldrb	w9, [x19]
	cbnz	w9, Ltr_show
	GADDR	x19, Ls_nothing
	ldr	x23, [x28, #G_SECOND]
	CSTR	x22, "Beam"
Ltr_show:
	ldr	x0, [x28, #G_TITLE]
	mov	x1, x19
	bl	setstr
	ldr	x0, [x28, #G_TITLE]
	mov	x2, x23
	SEND	S_setTextColor_
	ldr	x0, [x28, #G_ARTIST]
	mov	x1, x20
	bl	setstr
	ldrb	w9, [x20]                 ; a lone title sits in the middle of its row
	mov	w10, #(ROW2_C + 1)
	mov	w11, #(ROW2_C - 9)
	cmp	w9, #0
	csel	w9, w10, w11, ne
	scvtf	d1, w9
	fmov	d0, #16.0
	ldr	x0, [x28, #G_TITLE]
	SEND	S_setFrameOrigin_
	mov	x0, x22
	bl	mkstr
	mov	x2, x0
	ldr	x0, [x28, #G_WIN]
	SEND	S_setTitle_
	b	Lret3

; show_art(url) — load new artwork on the worker queue when the URL changed ("" hides it).
	.equ ART_GEN,	0                 ; request generation
	.equ ART_BUF,	8                 ; {data, len}
	.equ ART_URL,	24                ; the URL, inline
show_art:
	FRAME	2
	mov	x1, x0
	BADDR	x19, B_UIART
	mov	x0, x19
	mov	x2, #2048
	bl	cache_update
	cbz	w0, Lret2
	ldr	x20, [x28, #G_ARTGEN]
	add	x20, x20, #1
	str	x20, [x28, #G_ARTGEN]     ; older downloads become stale
	ldrb	w9, [x19]
	cbz	w9, Lsw_hide
	mov	x0, x19
	bl	_strlen
	add	x21, x0, #1               ; with its NUL
	add	x0, x0, #(ART_URL + 1)
	bl	_malloc
	cbz	x0, Lret2
	str	x20, [x0, #ART_GEN]
	stp	xzr, xzr, [x0, #ART_BUF]
	mov	x20, x0
	add	x0, x0, #ART_URL
	mov	x1, x19
	mov	x2, x21
	bl	_memcpy
	WORKQ
	mov	x1, x20
	adr	x2, art_fetch
	bl	_dispatch_async_f
	b	Lret2
Lsw_hide:
	mov	x0, #0
	mov	w1, #0
	bl	art_show
	b	Lret2

; art_fetch(job) — download the artwork, then hand it to the main thread.
	ENTRY	art_fetch
	FRAME	1
	mov	x20, x0
	bl	curl_new
	mov	x19, x0
	cbz	x0, Laf_done
	add	x0, x20, #ART_URL
	mov	x1, #0
	mov	x2, #0
	add	x3, x20, #ART_BUF
	mov	x4, #ART_TIMEOUT_MS
	bl	http
	mov	x0, x19
	bl	_curl_easy_cleanup
Laf_done:
	adr	x0, art_apply
	mov	x1, x20
	bl	post_main
	b	Lret1

; art_show(image, letterboxed) — show an image on the artwork card at its own shape (nil leaves the empty card), cropping a 4:3 thumbnail's bars.
art_show:
	FRAME	2
	mov	x19, x0
	mov	w20, w1
	ldr	x0, [x28, #G_ART]
	SEND	S_layer
	mov	x21, x0
	fmov	d0, xzr                   ; contentsRect, in unit coordinates
	fmov	d1, xzr
	fmov	d2, #1.0
	fmov	d3, #1.0
	cbz	w20, Las_rect
	fmov	d1, #0.125                ; skip 12.5% at the top and bottom
	fmov	d3, #0.75
Las_rect:
	SEND	S_setContentsRect_
	mov	x0, x21
	mov	x2, x19
	SEND	S_setContents_
	cmp	x19, #0
	cset	w9, ne
	str	w9, [x28, #G_ARTOK]
	fmov	d0, #1.0                  ; the card's height / width: square without an image
	cbz	x19, Las_aspect
	fmov	d0, #0.5625               ; 16:9 once the bars are cut
	cbnz	w20, Las_aspect
	mov	x0, x19
	SEND	S_size
	fdiv	d0, d1, d0
Las_aspect:
	str	d0, [x28, #G_ARTASP]
	bl	layout_stage
	bl	stage_update
	b	Lret2

; art_apply(job) — show the downloaded artwork, or the empty card if it is not an image.
	ENTRY	art_apply
	FRAME	2
	mov	x19, x0
	ldr	x9, [x28, #G_ARTGEN]
	ldr	x10, [x19, #ART_GEN]
	cmp	x9, x10
	b.ne	Laa_free                  ; superseded by a newer track
	ldp	x2, x3, [x19, #ART_BUF]
	cbz	x2, Laa_hide
	CLASS	x0, NSData
	SEND	S_dataWithBytes_length_
	mov	x20, x0
	CLASS	x0, NSImage
	SEND	S_alloc
	mov	x2, x20
	SEND	S_initWithData_
	mov	x20, x0
	cbz	x0, Laa_hide              ; not an image
	SEND	S_size
	fmov	d2, #3.0
	fmul	d0, d0, d2
	fmov	d2, #4.0
	fmul	d1, d1, d2
	fabd	d0, d0, d1                ; |3w - 4h| < 1: 4:3, a letterboxed 16:9 thumbnail
	fmov	d1, #1.0
	fcmp	d0, d1
	cset	w1, mi
	mov	x0, x20
	bl	art_show
	mov	x0, x20
	SEND	S_release                 ; the layer keeps it
	b	Laa_free
Laa_hide:
	mov	x0, #0
	mov	w1, #0
	bl	art_show
Laa_free:
	ldr	x0, [x19, #ART_BUF]
	bl	_free
	mov	x0, x19
	bl	_free
	b	Lret2

; layout_stage() — between the bar and the title bar: the artwork card as large as fits (at its shape), with the note, the spinner and the empty state centered on it.
layout_stage:
	FRAME	0
	ldr	x0, [x28, #G_CONTENT]
	SEND	S_bounds                  ; d2 = width, d3 = height
	mov	w9, #(STAGE_B + STAGE_T + 32)
	scvtf	d4, w9
	fsub	d3, d3, d4                ; the room's height, with some air
	mov	w9, #96
	scvtf	d4, w9
	fsub	d2, d2, d4                ; and width
	ldr	d5, [x28, #G_ARTASP]
	fdiv	d1, d3, d5
	fmin	d0, d2, d1                ; the widest card that fits both
	mov	w9, #ART_MAX
	scvtf	d4, w9
	fmin	d0, d0, d4
	mov	w9, #64
	scvtf	d4, w9
	fmax	d0, d0, d4
	fmul	d1, d0, d5
	fcvtzs	x0, d0
	fcvtzs	x1, d1
	ldr	x2, [x28, #G_ART]
	bl	center_box
	mov	x0, #96
	mov	x1, #96
	ldr	x2, [x28, #G_NOTE]
	bl	center_box
	mov	x0, #SPIN_S
	mov	x1, #SPIN_S
	ldr	x2, [x28, #G_SPIN]
	bl	center_box
	mov	x0, #EMPTY_W
	mov	x1, #EMPTY_H
	ldr	x2, [x28, #G_EMPTY]
	bl	center_box
	b	Lret0

; center_box(width, height, view) — give a view that size in the middle of the stage.
center_box:
	FRAME	1, 16
	mov	x19, x2
	stp	x0, x1, [sp]
	ldr	x0, [x28, #G_CONTENT]
	SEND	S_bounds
	ldp	x9, x10, [sp]
	scvtf	d4, x9
	scvtf	d5, x10
	fsub	d0, d2, d4
	mov	w11, #(STAGE_B + STAGE_T)
	scvtf	d6, w11
	fsub	d1, d3, d6
	fsub	d1, d1, d5
	fmov	d6, #0.5
	fmul	d0, d0, d6
	fmul	d1, d1, d6
	frintm	d0, d0                    ; whole points: crisp edges
	frintm	d1, d1
	mov	w11, #STAGE_B
	scvtf	d6, w11
	fadd	d1, d1, d6
	fmov	d2, d4
	fmov	d3, d5
	mov	x0, x19
	SEND	S_setFrame_
	b	Lret1

; stage_update() — what the stage shows: This Mac's picture, else the artwork card while a track plays or loads, else the empty state.
stage_update:
	FRAME	2
	mov	w19, #0                   ; the picture shows
	ldr	w9, [x28, #G_SEL]
	cbnz	w9, Lsu_pic
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, Lsu_pic
	ldr	w19, [x28, #G_HASVIDEO]
Lsu_pic:
	ldr	x0, [x28, #G_VIDEO]
	cmp	w19, #0
	cset	w2, eq
	SEND	S_setHidden_
	BADDR	x9, B_UITITLE
	ldrb	w9, [x9]
	cmp	w9, #0
	cset	w20, ne                   ; a track, or one on its way
	ldr	w9, [x28, #G_LOADING]
	orr	w20, w20, w9
	cmp	w19, #0
	csel	w20, wzr, w20, ne         ; the card, unless the picture covers it
	ldr	x0, [x28, #G_ART]
	eor	w2, w20, #1
	SEND	S_setHidden_
	ldr	w9, [x28, #G_ARTOK]
	eor	w10, w20, #1
	orr	w2, w9, w10               ; the note, on a card without an image, unless the spinner is there
	ldr	w9, [x28, #G_LOADING]
	orr	w2, w2, w9
	ldr	x0, [x28, #G_NOTE]
	SEND	S_setHidden_
	BADDR	x9, B_UITITLE
	ldrb	w9, [x9]
	ldr	w10, [x28, #G_LOADING]
	orr	w9, w9, w10
	orr	w9, w9, w19
	cmp	w9, #0
	cset	w2, ne
	ldr	x0, [x28, #G_EMPTY]
	SEND	S_setHidden_
	cbz	w19, Lsu_bar
	ldr	w9, [x28, #G_PPSHOWN]
	cbnz	w9, Lret2                 ; a playing picture may keep the bar away
Lsu_bar:
	bl	bar_show
	b	Lret2

; bar_show() — bring the control bar back.
bar_show:
	ldr	w9, [x28, #G_BARHID]
	cbz	w9, Lbs_ret
	str	wzr, [x28, #G_BARHID]
	fmov	d0, #1.0
; bar_alpha(alpha) — fade the control bar to an opacity.
bar_alpha:
	FRAME	0, 16
	str	d0, [sp]
	ldr	x0, [x28, #G_BAR]
	SEND	S_animator
	ldr	d0, [sp]
	SEND	S_setAlphaValue_
	b	Lret0
Lbs_ret:
	ret

; render_status() — a fresh message, else "not responding" for a silent device.
render_status:
	FRAME	1
	BADDR	x1, B_UIMSG
	ldr	w19, [x28, #G_MSGERR]
	ldrb	w9, [x1]
	cbz	w9, Lrs_hint
	ldr	x9, [x28, #G_TICK]
	ldr	x10, [x28, #G_MSGT]
	cmp	x9, x10
	b.le	Lrs_show
	strb	wzr, [x1]                 ; expired
Lrs_hint:
	mov	w19, #0                   ; hints are not errors
	GADDR	x1, Ls_slash+1
	ldr	w9, [x28, #G_READY]
	cbnz	w9, Lrs_show
	CSTR	x1, "The device is not responding."
Lrs_show:
	ldr	x0, [x28, #G_STATUS]
	bl	setstr
	ldr	x9, [x28, #G_SECOND]
	ldr	x10, [x28, #G_RED]
	cmp	w19, #0
	csel	x2, x10, x9, ne
	ldr	x0, [x28, #G_STATUS]
	SEND	S_setTextColor_
	b	Lret1

; add_item(menu, title, action, key) -> a new menu item; a nil target uses the responder chain.
add_item:
	FRAME	2
	mov	x19, x0
	mov	x20, x2
	mov	x21, x3
	mov	x0, x1
	bl	mkstr
	mov	x22, x0
	mov	x0, x21
	bl	mkstr
	mov	x4, x0
	mov	x0, x19
	mov	x2, x22
	mov	x3, x20
	SEND	S_addItemWithTitle_action_keyEquivalent_
	b	Lret2

; rebuild_devices() — the picker's items (after its face) from the device list; items that still match stay, so an open menu only grows.
rebuild_devices:
	FRAME	3, MAX_DEVS * DEV_SIZE
	mov	x22, sp                   ; a copy of the list
	LOCK
	ldr	w19, [x28, #G_DEVN]
	mov	x0, x22
	BADDR	x1, B_DEVS
	mov	x2, #(MAX_DEVS * DEV_SIZE)
	bl	_memcpy
	UNLOCK
	ldr	x0, [x28, #G_DEV]
	SEND	S_numberOfItems
	sub	x23, x0, #1               ; devices shown
	mov	x20, #0
Lrd_same:
	cmp	x20, x23
	ccmp	x20, x19, #2, lo
	b.hs	Lrd_cut
	ldr	x0, [x28, #G_DEV]
	add	x2, x20, #1
	SEND	S_itemTitleAtIndex_
	SEND	S_UTF8String
	mov	x9, #DEV_SIZE
	madd	x1, x20, x9, x22
	bl	_strcmp
	cbnz	w0, Lrd_cut
	add	x20, x20, #1
	b	Lrd_same
Lrd_cut:
	cmp	x23, x20
	b.ls	Lrd_add
	ldr	x0, [x28, #G_DEV]
	mov	x2, x23                   ; the last one shown, after the face
	SEND	S_removeItemAtIndex_
	sub	x23, x23, #1
	b	Lrd_cut
Lrd_add:
	cmp	x20, x19
	b.hs	Lret3
	ldr	x0, [x28, #G_DEV]
	SEND	S_menu                    ; the menu allows duplicate names
	mov	x9, #DEV_SIZE
	madd	x1, x20, x9, x22          ; the name
	mov	x2, #0
	GADDR	x3, Ls_slash+1
	bl	add_item
	mov	x21, x0
	CSTR	x0, "hifispeaker.fill"
	CSTR	x9, "laptopcomputer"
	cmp	x20, #0
	csel	x0, x9, x0, eq            ; This Mac, or a network device
	GADDR	x1, Ls_slash+1
	bl	symbol
	mov	x2, x0
	mov	x0, x21
	SEND	S_setImage_
	add	x20, x20, #1
	b	Lrd_add

; mark_devices(selected) — the selected device's checkmark, and a lit face while a network device plays.
mark_devices:
	FRAME	2
	mov	w19, w0
	ldr	x0, [x28, #G_DEV]
	SEND	S_numberOfItems
	mov	x20, x0
Lmk_item:
	subs	x20, x20, #1
	b.le	Lmk_face
	ldr	x0, [x28, #G_DEV]
	mov	x2, x20
	SEND	S_itemAtIndex_
	sub	x9, x20, #1
	cmp	x9, w19, uxtw
	cset	w2, eq
	SEND	S_setState_
	b	Lmk_item
Lmk_face:
	cmp	w19, #0
	cset	w9, ne
	ldr	w10, [x28, #G_DEVON]
	cmp	w9, w10
	b.eq	Lret2
	str	w9, [x28, #G_DEVON]
	ldr	x10, [x28, #G_IMGDEV]
	ldr	x11, [x28, #G_IMGDEVON]
	cmp	w9, #0
	csel	x21, x11, x10, ne
	ldr	x0, [x28, #G_DEV]
	mov	x2, #0
	SEND	S_itemAtIndex_
	mov	x2, x21
	SEND	S_setImage_
	b	Lret2

; set_status(message, is_error) — show a message for STATUS_TICKS seconds.
set_status:
	FRAME	1
	mov	w19, w1
	mov	x1, x0
	BADDR	x0, B_UIMSG
	mov	x2, #256
	bl	_strlcpy
	str	w19, [x28, #G_MSGERR]
	ldr	x9, [x28, #G_TICK]
	add	x9, x9, #STATUS_TICKS
	str	x9, [x28, #G_MSGT]
	bl	render_status
	b	Lret1

; ui_error_cb(message) — main-queue side of ui_post_error.
	ENTRY	ui_error_cb
	mov	w1, #1
	b	set_status

; ui_refresh — copy the snapshot under the lock and render all of it.
	ENTRY	ui_refresh
	FRAME	4, NOW_SIZE + 16
	mov	x19, sp
	LOCK
	mov	x0, x19
	BADDR	x1, B_NOW
	mov	x2, #NOW_SIZE
	bl	_memcpy
	UNLOCK
	ldr	w20, [x19, #NOW_SEL]
	ldr	w21, [x19, #NOW_STATE]
	cmp	w21, #ST_OFFLINE
	cset	w22, ne                   ; the device answers
	cmp	w20, #0
	csinc	w22, w22, wzr, ne         ; This Mac always does
	str	w20, [x28, #G_SEL]
	str	w22, [x28, #G_READY]
	ldr	w9, [x19, #NOW_DEVREV]
	ldr	w10, [x28, #G_DEVREV]
	cmp	w9, w10
	b.eq	Lur_pick
	str	w9, [x28, #G_DEVREV]
	bl	rebuild_devices
Lur_pick:
	mov	w0, w20
	bl	mark_devices
	add	x0, x19, #NOW_TITLE
	add	x1, x19, #NOW_ARTIST
	bl	show_track
	add	x0, x19, #NOW_ART
	bl	show_art
	cmp	w21, #ST_PLAYING
	ccmp	w21, #ST_TRANSITIONING, #4, ne
	cset	w23, eq                   ; playing, or about to
	ldr	w10, [x28, #G_PPSHOWN]
	cmp	w10, w23
	b.eq	Lur_enable
	str	w23, [x28, #G_PPSHOWN]
	ldr	x10, [x28, #G_IMGPAUSE]
	ldr	x11, [x28, #G_IMGPLAY]
	cmp	w23, #0
	csel	x2, x10, x11, ne
	ldr	x0, [x28, #G_PP]
	SEND	S_setImage_
Lur_enable:
	ldp	x24, x25, [x19, #NOW_POS]
	cmp	x25, #0
	csel	w26, w22, wzr, gt         ; seekable: answering, with a known duration
	mov	x23, #G_BACK
Lur_each:
	ldr	x0, [x28, x23]
	cmp	x23, #G_PP
	csel	w2, w26, w22, lo
	SEND	S_setEnabled_
	add	x23, x23, #8
	cmp	x23, #(G_VOL + 8)
	b.lo	Lur_each
	ldr	w9, [x28, #G_SEEKDRAG]
	cbnz	w9, Lur_volume            ; the user is dragging it
	ldr	x9, [x28, #G_TICK]
	ldr	x10, [x28, #G_SEEKH]
	cmp	x9, x10
	b.lo	Lur_volume                ; a seek is still settling
	mov	x0, x24
	mov	x1, x25
	bl	show_time
Lur_volume:
	ldr	w9, [x28, #G_VOLDRAG]
	cbnz	w9, Lur_mute
	ldr	x9, [x28, #G_TICK]
	ldr	x10, [x28, #G_VOLH]
	cmp	x9, x10
	b.lo	Lur_mute                  ; a volume change is still settling
	ldr	w9, [x19, #NOW_VOL]
	scvtf	d0, w9
	ldr	x0, [x28, #G_VOL]
	SEND	S_setDoubleValue_
Lur_mute:
	ldr	w9, [x19, #NOW_MUTE]
	ldr	w10, [x28, #G_MUTESHOWN]
	cmp	w9, w10
	b.eq	Lur_status
	str	w9, [x28, #G_MUTESHOWN]
	ldr	x10, [x28, #G_IMGMUTED]
	ldr	x11, [x28, #G_IMGUNMUTED]
	cmp	w9, #0
	csel	x2, x10, x11, ne
	ldr	x0, [x28, #G_MUTE]
	SEND	S_setImage_
Lur_status:
	bl	render_status
	bl	stage_update
	b	Lret4

; show_time(pos, dur) — position slider, elapsed time and time left.
show_time:
	FRAME	2, 32
	mov	x19, x0
	mov	x20, x1
	mov	x9, #1
	cmp	x20, #0
	csel	x9, x20, x9, gt           ; range: the duration (1 when unknown)
	scvtf	d0, x9
	ldr	x0, [x28, #G_POS]
	SEND	S_setMaxValue_
	cmp	x19, x20
	csel	x9, x19, x20, lt          ; within the track
	cmp	x20, #0
	csel	x9, x9, xzr, gt
	scvtf	d0, x9
	ldr	x0, [x28, #G_POS]
	SEND	S_setDoubleValue_
	mov	x0, x19
	mov	x1, sp
	mov	x2, #0
	bl	fmt_time
	ldr	x0, [x28, #G_CUR]
	mov	x1, sp
	bl	setstr
	GADDR	x1, Ls_dashes
	cmp	x20, #0
	b.le	Lst_left
	cmp	x19, x20
	csel	x0, x19, x20, lt
	sub	x0, x20, x0               ; time left
	add	x1, sp, #1
	mov	x2, #0
	bl	fmt_time
	mov	w9, #'-'
	strb	w9, [sp]
	mov	x1, sp
Lst_left:
	ldr	x0, [x28, #G_DUR]
	bl	setstr
	b	Lret2

; ui_play_done(job) — end loading, report the result, free the job.
	ENTRY	ui_play_done
	FRAME	2, 272
	mov	x19, x0
	str	wzr, [x28, #G_LOADING]
	ADDR	x0, Lprog_idle
	bl	ui_run
	ldr	w20, [x19, #JOB_RESULT]
	cbnz	w20, Lpd_failed
	ADDR	x0, Lprog_played
	bl	ui_run
	ldr	w9, [x28, #G_SEL]
	cbnz	w9, Lpd_cleared
	mov	x0, x19
	bl	local_play
Lpd_cleared:
	GADDR	x0, Ls_slash+1
	mov	w1, #0
	b	Lpd_message
Lpd_failed:
	CSTR	x0, "The device rejected the track."
	cmp	w20, #PLAY_REJECTED
	b.eq	Lpd_error
	CSTR	x0, "Could not load the link."
	ldr	x9, [x19, #JOB_ERR]
	cbz	x9, Lpd_error
	str	x9, [sp]                  ; the resolver's own explanation
	add	x0, sp, #16
	mov	x1, #256
	CSTR	x2, "Could not load: %s"
	bl	_snprintf
	add	x0, sp, #16
Lpd_error:
	mov	w1, #1
Lpd_message:
	bl	set_status
	ldr	x0, [x19, #JOB_ITEM]      ; unused if the device changed meanwhile
	SEND	S_release
	ldr	x0, [x19, #JOB_QUERY]
	bl	_free
	mov	x0, x19
	bl	_free
	bl	Lui_refresh
	b	Lret2

; ---- This Mac: AVPlayer; macOS routes the sound to the chosen output (speakers, Bluetooth, AirPlay) ----

; local_play(job) — play the prepared item on This Mac.
local_play:
	FRAME	1
	mov	x19, x0
	BADDR	x0, B_LTTRACK
	add	x1, x19, #JOB_TRACK
	mov	x2, #T_SIZE
	bl	_memcpy
	ldr	x9, [x19, #JOB_DUR]
	str	x9, [x28, #G_LTDUR]
	BADDR	x0, B_LTAURL              ; YouTube's streams, to drop or fetch the picture later
	ADDO	x1, x19, JOB_HLSA
	ldrb	w9, [x1]
	ADDO	x10, x19, JOB_LOCAL
	cmp	w9, #0
	csel	x1, x1, x10, ne
	mov	x2, #256
	bl	_strlcpy
	ADDO	x1, x19, JOB_HLS          ; the picture: our HLS, or a broadcast's own
	ldr	w9, [x19, #JOB_LIVE]
	cbz	w9, Llp_keep
	ADDO	x1, x19, JOB_VURL
Llp_keep:
	BADDR	x0, B_LTVURL
	mov	x2, #4096
	bl	_strlcpy
	str	wzr, [x28, #G_FAILED]
	str	wzr, [x28, #G_HASVIDEO]
	str	wzr, [x28, #G_IDLE]       ; the controls stay a moment on a new track
	bl	resume_stop
	ldr	x2, [x19, #JOB_ITEM]
	cbz	x2, Llp_none
	str	xzr, [x19, #JOB_ITEM]
	mov	x20, x2
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_replaceCurrentItemWithPlayerItem_
	mov	x0, x20
	SEND	S_release
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_play
	bl	local_poll
	b	Lret1
Llp_none:
	CSTR	x0, "Could not play this media."
	mov	w1, #1
	bl	set_status
	b	Lret1

; local_poll() — publish This Mac's playback state (its own duration and picture, once known) and re-render.
local_poll:
	FRAME	4, 48                     ; a CMTime at sp + 16
	ldr	x19, [x28, #G_PLAYER]
	mov	x0, x19
	SEND	S_currentItem
	mov	x24, x0
	mov	w20, #ST_STOPPED
	mov	w25, #0                   ; a picture
	cbz	x0, Llq_time              ; nothing loaded
	SEND	S_status
	cmp	x0, #PLAYER_ITEM_FAILED
	b.ne	Llq_item
	ldr	w9, [x28, #G_FAILED]
	cbnz	w9, Llq_time
	mov	w9, #1
	str	w9, [x28, #G_FAILED]
	CSTR	x0, "Could not play this media."
	mov	w1, #1
	bl	set_status
	b	Llq_time
Llq_item:
	ldr	x9, [x28, #G_LTDUR]
	cbnz	x9, Llq_size              ; YouTube said it
	mov	x0, x24
	add	x8, sp, #16
	SEND	S_duration
	ldr	w9, [sp, #28]             ; flags: valid, and not indefinite or infinite
	mov	w10, #0x1d
	and	w9, w9, w10
	cmp	w9, #1
	b.ne	Llq_size
	ldr	x9, [sp, #16]
	ldrsw	x10, [sp, #24]
	sdiv	x9, x9, x10
	str	x9, [x28, #G_LTDUR]
Llq_size:
	mov	x0, x24
	SEND	S_presentationSize        ; d0 = width, 0 without a picture
	fcmp	d0, #0.0
	cset	w25, gt
	mov	x0, x24
	bl	video_tracks
	mov	x0, x19
	SEND	S_timeControlStatus
	mov	w20, #ST_PAUSED
	mov	w9, #ST_TRANSITIONING
	cmp	x0, #AVPLAYER_WAITING
	csel	w20, w9, w20, eq
	mov	w9, #ST_PLAYING
	cmp	x0, #AVPLAYER_PLAYING
	csel	w20, w9, w20, eq
Llq_time:
	mov	x0, x19
	add	x8, sp, #16               ; a CMTime comes back through x8
	SEND	S_currentTime
	ldr	x9, [sp, #16]             ; value / timescale (0 / 0 with no item gives 0)
	ldrsw	x10, [sp, #24]
	sdiv	x21, x9, x10
	mov	x0, x19
	SEND	S_volume
	ldr	s1, [x28, #(Lf_100 - G)]
	fmul	s0, s0, s1
	fcvtns	w22, s0
	mov	x0, x19
	SEND	S_isMuted
	mov	w23, w0
	LOCK
	BADDR	x26, B_NOW
	ldr	w9, [x26, #NOW_SEL]
	cbnz	w9, Llq_unlock            ; a device owns the snapshot now
	str	w20, [x26, #NOW_STATE]
	stp	w22, w23, [x26, #NOW_VOL]
	ldr	x9, [x28, #G_LTDUR]
	stp	x21, x9, [x26, #NOW_POS]
	add	x0, x26, #NOW_TITLE
	BADDR	x1, B_LTTRACK
	mov	x2, #T_SIZE
	bl	_memcpy
Llq_unlock:
	UNLOCK
	str	w25, [x28, #G_HASVIDEO]
	bl	Lui_refresh
	b	Lret4

; video_tracks(item) — Audio Only turns the item's picture tracks off (nothing is decoded), and back on.
video_tracks:
	FRAME	3
	SEND	S_tracks
	mov	x19, x0
	SEND	S_count
	mov	x20, x0
	ldr	w9, [x28, #G_AONLY]
	eor	w21, w9, #1
	CSTR	x0, "vide"
	bl	mkstr
	mov	x22, x0
Lvt_next:
	subs	x20, x20, #1
	b.lt	Lret3
	mov	x0, x19
	mov	x2, x20
	SEND	S_objectAtIndex_
	mov	x23, x0
	SEND	S_assetTrack
	SEND	S_mediaType
	mov	x2, x22
	SEND	S_isEqualToString_
	cbz	w0, Lvt_next
	mov	x0, x23
	SEND	S_isEnabled
	cmp	w0, w21
	b.eq	Lvt_next
	mov	x0, x23
	mov	w2, w21
	SEND	S_setEnabled_
	b	Lvt_next

; local_toggle() — play or pause This Mac.
local_toggle:
	FRAME	0
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_timeControlStatus
	cmp	x0, #0                    ; paused: play
	ldr	x9, [x27, #S_play]
	ldr	x1, [x27, #S_pause]
	csel	x1, x9, x1, eq
	ldr	x0, [x28, #G_PLAYER]
	bl	_objc_msgSend
	bl	local_poll
	b	Lret0

; local_seek(seconds) — jump to a position on This Mac.
local_seek:
	mov	x9, #1000
	mul	x0, x0, x9
; local_seekms(ms) — the same, to the millisecond.
local_seekms:
	FRAME	0, 48
	cmp	x0, #0
	csel	x0, x0, xzr, gt
	mov	x9, #1000                 ; CMTime in milliseconds: value, timescale, flags (valid), epoch
	movk	x9, #1, lsl #32
	stp	x0, x9, [sp]
	str	xzr, [sp, #16]
	mov	x9, #1                    ; zero tolerance: the exact moment, not the segment's start
	movk	x9, #1, lsl #32
	stp	xzr, x9, [sp, #24]
	str	xzr, [sp, #40]
	ldr	x0, [x28, #G_PLAYER]
	mov	x2, sp                    ; passed by reference
	add	x3, sp, #24
	add	x4, sp, #24
	SEND	S_seekToTime_toleranceBefore_toleranceAfter_
	bl	local_poll
	b	Lret0

; local_stop() — pause and rewind This Mac.
local_stop:
	FRAME	0
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_pause
	mov	x0, #0
	bl	local_seek
	b	Lret0

; local_setvol(level) — This Mac's player volume, 0..100; unmutes.
local_setvol:
	FRAME	1
	mov	w19, w0
	ldr	x0, [x28, #G_PLAYER]
	scvtf	s0, w19
	ldr	s1, [x28, #(Lf_100 - G)]
	fdiv	s0, s0, s1
	SEND	S_setVolume_
	ldr	x0, [x28, #G_PLAYER]
	mov	w2, #0
	SEND	S_setMuted_
	bl	local_poll
	b	Lret1

; local_volstep(delta) — change This Mac's volume by delta, within 0..100.
local_volstep:
	FRAME	1
	mov	w19, w0
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_volume
	ldr	s1, [x28, #(Lf_100 - G)]
	fmul	s0, s0, s1
	fcvtns	w0, s0
	add	w0, w0, w19
	bl	clamp100
	bl	local_setvol
	b	Lret1

; local_mute() — toggle This Mac's mute.
local_mute:
	FRAME	1
	ldr	x0, [x28, #G_PLAYER]
	mov	x19, x0
	SEND	S_isMuted
	eor	w2, w0, #1
	mov	x0, x19
	SEND	S_setMuted_
	bl	local_poll
	b	Lret1

; local_swap() — Audio Only changed on a YouTube video: the item becomes its sound alone (no picture bytes fetched) or its HLS presentation again; act_resume puts it back where it was.
local_swap:
	FRAME	1, 32                     ; a CMTime at sp
	ldr	x0, [x28, #G_PLAYER]
	mov	x8, sp
	SEND	S_currentTime
	ldp	x9, x10, [sp]             ; value, timescale
	mov	x11, #1000
	mul	x9, x9, x11
	sxtw	x10, w10
	cbz	x10, Lret1
	sdiv	x9, x9, x10
	ldr	x10, [x28, #G_LTDUR]
	cmp	x10, #0
	csinv	x9, x9, xzr, ne           ; a broadcast (no length) just goes on: -1
	str	x9, [x28, #G_RESUMEMS]
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_timeControlStatus
	str	w0, [x28, #G_RESUMEPLAY]  ; playing, or about to
	BADDR	x0, B_LTAURL
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, Lsw_make
	BADDR	x0, B_LTVURL
Lsw_make:
	bl	make_item
	cbz	x0, Lret1
	mov	x19, x0
	ldr	x0, [x28, #G_PLAYER]      ; silent until it is back in place
	SEND	S_pause
	ldr	x0, [x28, #G_PLAYER]
	mov	x2, x19
	SEND	S_replaceCurrentItemWithPlayerItem_
	mov	x0, x19
	SEND	S_release
	str	wzr, [x28, #G_HASVIDEO]
	bl	resume_stop
	ADDR	x0, Lprog_resume
	bl	ui_run
	b	Lret1

; act_resume(timer) — every quarter second until the swapped item is ready: then the saved moment, and play if it was playing.
	ENTRY	act_resume
	FRAME	1
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_currentItem
	SEND	S_status
	cbz	x0, Lret1                 ; still loading
	mov	x19, x0
	bl	resume_stop
	cmp	x19, #PLAYER_ITEM_FAILED
	b.eq	Lret1
	ldr	x0, [x28, #G_RESUMEMS]
	tbnz	x0, #63, Lrm_play
	bl	local_seekms
Lrm_play:
	ldr	w9, [x28, #G_RESUMEPLAY]
	cbz	w9, Lret1
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_play
	bl	local_poll
	b	Lret1

; resume_stop() — no pending return to a moment (a new track, or it happened).
resume_stop:
	FRAME	0
	ldr	x0, [x28, #G_RESUMET]
	str	xzr, [x28, #G_RESUMET]
	SEND	S_invalidate
	b	Lret0

; ---- Actions (Objective-C methods: self, _cmd, sender) ----

; enqueue(work, context) — run work on the device queue when the device answers.
enqueue:
	ldr	w9, [x28, #G_READY]
	cbz	w9, Leq_ret
	mov	x2, x0
	ldr	x0, [x28, #G_QUEUE]
	b	_dispatch_async_f
Leq_ret:
	ret

; route(job, context, local) — This Mac runs local(context) now; a device gets job(context) on its queue.
route:
	ldr	w9, [x28, #G_SEL]
	cbnz	w9, enqueue
	mov	x0, x1
	br	x2

; act_toggle — the play/pause button and Space.
	ENTRY	act_toggle
	adr	x0, toggle_job
	mov	x1, #0
	adr	x2, local_toggle
	b	route

; act_stop — Cmd-.
	ENTRY	act_stop
	adr	x0, stop_job
	mov	x1, #0
	adr	x2, local_stop
	b	route

; act_back / act_fwd — the 10-second skips and Cmd-Left / Cmd-Right.
	ENTRY	act_back
	mov	x0, #-SKIP_SECONDS
	b	skip
	ENTRY	act_fwd
	mov	x0, #SKIP_SECONDS

; skip(delta) — seek from the position on screen and show the target at once, inside the track.
skip:
	FRAME	2
	mov	x19, x0
	ldr	x0, [x28, #G_POS]
	SEND	S_isEnabled
	cbz	w0, Lret2                 ; unknown duration: nowhere to skip to
	ldr	x0, [x28, #G_POS]
	SEND	S_maxValue
	fcvtzs	x20, d0
	ldr	x0, [x28, #G_POS]
	SEND	S_doubleValue
	fcvtzs	x9, d0
	add	x19, x9, x19
	sub	x9, x20, #1               ; at most the last second
	cmp	x19, x9
	csel	x19, x19, x9, lt
	cmp	x19, #0
	csel	x19, x19, xzr, gt
	mov	x0, x19
	mov	x1, x20
	bl	show_time
	mov	x1, x19
	bl	seek_route
	b	Lret2

; seek_route(_, seconds) — hold polled positions for the seek, then send it.
seek_route:
	ldr	x9, [x28, #G_TICK]
	add	x9, x9, #HOLD_TICKS
	str	x9, [x28, #G_SEEKH]
	adr	x0, seek_job
	adr	x2, local_seek
	b	route

; act_volup / act_voldown — Cmd-Up / Cmd-Down: one volume step.
	ENTRY	act_volup
	mov	x1, #VOLUME_STEP
	b	volstep
	ENTRY	act_voldown
	mov	x1, #-VOLUME_STEP
volstep:
	adr	x0, volstep_job
	adr	x2, local_volstep
	b	route

; act_mute — the mute button and Opt-Cmd-Down.
	ENTRY	act_mute
	adr	x0, mute_job
	mov	x1, #0
	adr	x2, local_mute
	b	route

; act_device — the device picker: switch the playback target.
	ENTRY	act_device
	FRAME	1
	ldr	x0, [x28, #G_DEV]
	SEND	S_indexOfSelectedItem
	subs	x19, x0, #1               ; after the face
	b.lt	Lret1
	ldr	w9, [x28, #G_SEL]
	cmp	w9, w19
	b.eq	Lret1                     ; the same device
	cbnz	w9, Lad_switch
	ldr	x0, [x28, #G_PLAYER]      ; leaving This Mac: stop playing here
	SEND	S_pause
Lad_switch:
	str	w19, [x28, #G_SEL]        ; route new actions right away
	ldr	x0, [x28, #G_QUEUE]
	mov	x1, x19
	adr	x2, select_job
	bl	_dispatch_async_f
	b	Lret1

; dragging() — w0 = 1 while the mouse button is still down.
dragging:
	FRAME	0
	ldr	x0, [x28, #G_APP]
	SEND	S_currentEvent
	SEND	S_type                    ; a nil event gives 0
	cmp	x0, #NSEventTypeLeftMouseDown
	ccmp	x0, #NSEventTypeLeftMouseDragged, #4, ne
	cset	w0, eq
	b	Lret0

; play_text(text) — resolve and play a link, search, web address or file path (copied), one at a time.
play_text:
	FRAME	2
	mov	x19, x0
	ldrb	w9, [x19]
	cbz	w9, Lret2                 ; empty
	ldr	w9, [x28, #G_LOADING]
	cbnz	w9, Lret2
	ldr	w9, [x28, #G_READY]
	cbnz	w9, Lpt_go
	CSTR	x0, "No device available."
	mov	w1, #1
	bl	set_status
	b	Lret2
Lpt_go:
	mov	x0, #1
	mov	x1, #JOB_SIZE
	bl	_calloc
	cbz	x0, Lret2
	mov	x20, x0
	mov	x0, x19
	bl	_strdup                   ; the caller's text dies with its pool
	str	x0, [x20, #JOB_QUERY]
	cbz	x0, Lpt_drop
	mov	w9, #1
	str	w9, [x28, #G_LOADING]
	ADDR	x0, Lprog_busy
	bl	ui_run
	GADDR	x0, Ls_slash+1
	mov	w1, #0
	bl	set_status
	bl	stage_update
	WORKQ
	mov	x1, x20
	adr	x2, play_resolve
	bl	_dispatch_async_f
	b	Lret2
Lpt_drop:
	mov	x0, x20
	bl	_free
	b	Lret2

; play_url(url) — play an NSURL: a file by its path, anything else by its text.
play_url:
	FRAME	1
	mov	x19, x0
	SEND	S_isFileURL
	mov	x9, x0
	mov	x0, x19
	cbz	w9, Lpu_web
	SEND	S_path
	b	Lpu_text
Lpu_web:
	SEND	S_absoluteString
Lpu_text:
	SEND	S_UTF8String
	cbz	x0, Lret1
	bl	play_text
	b	Lret1

; act_play — Return in the link field: play what it holds.
	ENTRY	act_play
	FRAME	1
	ldr	x0, [x28, #G_FIELD]
	SEND	S_stringValue
	mov	x19, x0
	CLASS	x0, NSCharacterSet
	SEND	S_whitespaceAndNewlineCharacterSet
	mov	x2, x0
	mov	x0, x19
	SEND	S_stringByTrimmingCharactersInSet_
	SEND	S_UTF8String
	mov	x19, x0
	bl	url_hide
	cbz	x19, Lret1
	mov	x0, x19
	bl	play_text
	b	Lret1

; act_focus — Open from URL (Cmd-L): the link field floats in, ready to paste.
	ENTRY	act_focus
	ADDR	x0, Lprog_focus
	b	ui_run

; url_hide() — the link field goes away and the window keeps the keyboard.
url_hide:
	FRAME	0
	ldr	x0, [x28, #G_URLBOX]
	SEND	S_isHidden
	cbnz	w0, Lret0                 ; already
	ADDR	x0, Lprog_urlhide
	bl	ui_run
	b	Lret0

; act_urlcmd(control, text view, command) -> YES for Escape, which closes the link field.
	ENTRY	act_urlcmd
	FRAME	0
	ldr	x9, [x27, #S_cancelOperation_]
	mov	w0, #0
	cmp	x4, x9
	b.ne	Lret0
	bl	url_hide
	mov	w0, #1
	b	Lret0

; act_open — Open (Cmd-O): pick an audio or video file.
	ENTRY	act_open
	FRAME	1
	CLASS	x0, NSOpenPanel
	SEND	S_openPanel
	mov	x19, x0
	CSTR	x0, "public.audiovisual-content"
	bl	mkstr
	mov	x2, x0
	CLASS	x0, UTType
	SEND	S_typeWithIdentifier_
	mov	x2, x0
	CLASS	x0, NSArray
	SEND	S_arrayWithObject_
	mov	x2, x0
	mov	x0, x19
	SEND	S_setAllowedContentTypes_
	mov	x0, x19
	SEND	S_runModal
	cmp	x0, #1                    ; NSModalResponseOK
	b.ne	Lret1
	mov	x0, x19
	SEND	S_URL
	bl	play_url
	b	Lret1

; act_openurls(app, urls) — files opened with Beam from the Finder or the Dock.
	ENTRY	act_openurls
	FRAME	0
	mov	x0, x3
	SEND	S_firstObject
	cbz	x0, Lret0
	bl	play_url
	b	Lret0

; act_drop(drag) -> YES when a dropped file, link or text was taken.
	ENTRY	act_drop
	FRAME	1
	mov	x0, x2
	SEND	S_draggingPasteboard
	mov	x19, x0
	CLASS	x2, NSURL
	CLASS	x0, NSArray
	SEND	S_arrayWithObject_
	mov	x2, x0
	mov	x0, x19
	mov	x3, #0
	SEND	S_readObjectsForClasses_options_
	SEND	S_firstObject
	cbz	x0, Ldp_text
	bl	play_url
	mov	w0, #1
	b	Lret1
Ldp_text:
	CSTR	x0, "public.utf8-plain-text"
	bl	mkstr
	mov	x2, x0
	mov	x0, x19
	SEND	S_stringForType_
	SEND	S_UTF8String
	cbz	x0, Lret1
	bl	play_text
	mov	w0, #1
	b	Lret1

; act_click(event) — a click on the stage closes the link field; a double click toggles full screen.
	ENTRY	act_click
	FRAME	1
	mov	x19, x2
	bl	url_hide
	mov	x0, x19
	SEND	S_clickCount
	cmp	x0, #2
	b.ne	Lret1
	ldr	x0, [x28, #G_WIN]
	mov	x2, #0
	SEND	S_toggleFullScreen_
	b	Lret1

; act_moved(event) — the mouse moved: the controls come back, and note whether it is over them.
	ENTRY	act_moved
	FRAME	0
	str	wzr, [x28, #G_IDLE]
	mov	x0, x2
	SEND	S_locationInWindow        ; d1 = height above the bottom
	mov	w9, #(BAR_M + BAR_H + 8)
	scvtf	d2, w9
	fcmp	d1, d2
	cset	w9, mi
	str	w9, [x28, #G_HOVER]
	bl	bar_show
	b	Lret0

; act_aonly — Audio Only (the headphones and Opt-Cmd-A): no picture is fetched, decoded or shown.
	ENTRY	act_aonly
	FRAME	1
	ldr	w9, [x28, #G_AONLY]
	eor	w19, w9, #1
	str	w19, [x28, #G_AONLY]
	ldr	x0, [x28, #G_AOITEM]
	mov	w2, w19
	SEND	S_setState_
	ldr	x9, [x28, #G_YEL]
	ldr	x10, [x28, #G_SECOND]
	cmp	w19, #0
	csel	x2, x9, x10, ne
	ldr	x0, [x28, #G_AOBTN]
	SEND	S_setContentTintColor_
	ldr	w9, [x28, #G_SEL]
	cbnz	w9, Lao_stage             ; speakers play sound only anyway
	BADDR	x9, B_LTVURL
	ldrb	w9, [x9]
	cbz	w9, Lao_poll              ; a file or web media: its picture tracks switch in place
	bl	local_swap
Lao_poll:
	bl	local_poll
	b	Lret1
Lao_stage:
	bl	stage_update
	b	Lret1

; act_vol — the volume slider; a device gets at most one queued job, always with the latest value.
	ENTRY	act_vol
	FRAME	1
	ldr	w9, [x28, #G_READY]
	cbz	w9, Lret1
	ldr	x0, [x28, #G_VOL]
	SEND	S_intValue
	mov	w19, w0
	bl	dragging
	str	w0, [x28, #G_VOLDRAG]
	ldr	x9, [x28, #G_TICK]
	add	x9, x9, #HOLD_TICKS
	str	x9, [x28, #G_VOLH]
	ldr	w9, [x28, #G_SEL]
	cbnz	w9, Lav_device
	mov	w0, w19
	bl	local_setvol
	b	Lret1
Lav_device:
	add	x9, x28, #G_PVOL
	stlr	w19, [x9]
	add	x9, x28, #G_VOLB
	mov	w10, #1
	swpal	w10, w10, [x9]            ; claim the single queue slot
	cbnz	w10, Lret1                ; already queued: it reads the new value
	ldr	x0, [x28, #G_QUEUE]
	mov	x1, #0
	adr	x2, vol_job
	bl	_dispatch_async_f
	b	Lret1

; act_seek — the position slider: This Mac follows the drag frame by frame; a device seeks when it is released.
	ENTRY	act_seek
	FRAME	1
	ldr	w9, [x28, #G_READY]
	cbz	w9, Lret1
	ldr	x0, [x28, #G_POS]
	SEND	S_doubleValue
	fcvtzs	x19, d0
	ldr	x0, [x28, #G_POS]
	SEND	S_maxValue
	fcvtzs	x1, d0
	mov	x0, x19
	bl	show_time
	bl	dragging
	str	w0, [x28, #G_SEEKDRAG]
	cbz	w0, Lsk_release
	ldr	w9, [x28, #G_SEL]
	cbnz	w9, Lret1
	mov	x0, x19
	bl	local_seek
	b	Lret1
Lsk_release:
	mov	x1, x19
	bl	seek_route
	b	Lret1

; act_tick — the 1 Hz timer: the controls' idle fade; This Mac renders itself; a device is polled, one poll in flight at most.
	ENTRY	act_tick
	FRAME	0
	ldr	x10, [x28, #G_TICK]
	add	x10, x10, #1
	str	x10, [x28, #G_TICK]
	bl	idle_tick
	ldr	w9, [x28, #G_SEL]
	cbnz	w9, Lat_device
	bl	local_poll
	b	Lret0
Lat_device:
	add	x9, x28, #G_POLLB
	mov	w10, #1
	swpal	w10, w10, [x9]
	cbnz	w10, Lret0                ; the previous poll is still running
	ldr	x0, [x28, #G_QUEUE]
	mov	x1, #0
	adr	x2, poll_job
	bl	_dispatch_async_f
	b	Lret0

; idle_tick() — a picture playing on This Mac: after a few still seconds the controls and the pointer fade away.
idle_tick:
	FRAME	0
	ldr	w9, [x28, #G_IDLE]
	add	w9, w9, #1
	str	w9, [x28, #G_IDLE]
	cmp	w9, #HIDE_TICKS
	b.lo	Lret0
	ldr	w9, [x28, #G_BARHID]
	ldr	w10, [x28, #G_HOVER]
	orr	w9, w9, w10
	ldr	w10, [x28, #G_SEL]
	orr	w9, w9, w10
	ldr	w10, [x28, #G_AONLY]
	orr	w9, w9, w10
	cbnz	w9, Lret0
	ldr	w9, [x28, #G_HASVIDEO]
	ldr	w10, [x28, #G_PPSHOWN]
	and	w9, w9, w10
	cbz	w9, Lret0
	ldr	x0, [x28, #G_URLBOX]
	SEND	S_isHidden
	cbz	w0, Lret0                 ; a link is being typed
	mov	w9, #1
	str	w9, [x28, #G_BARHID]
	fmov	d0, xzr
	bl	bar_alpha
	CLASS	x0, NSCursor
	mov	w2, #1
	SEND	S_setHiddenUntilMouseMoves_
	b	Lret0

; act_key(event) — keys on the stage: Space plays and pauses, arrows skip and change the volume, F toggles full screen (Escape leaves it), M mutes.
	ENTRY	act_key
	FRAME	0
	mov	x0, x2
	SEND	S_keyCode
	cmp	x0, #49                   ; Space
	b.eq	Lak_toggle
	cmp	x0, #123                  ; left
	b.eq	Lak_back
	cmp	x0, #124                  ; right
	b.eq	Lak_fwd
	cmp	x0, #126                  ; up
	b.eq	Lak_up
	cmp	x0, #125                  ; down
	b.eq	Lak_down
	cmp	x0, #46                   ; M
	b.eq	Lak_mute
	cmp	x0, #3                    ; F
	b.eq	Lak_full
	cmp	x0, #53                   ; Escape
	b.ne	Lret0
	ldr	x0, [x28, #G_WIN]
	SEND	S_styleMask
	tbz	x0, #14, Lret0            ; not full screen
Lak_full:
	ldr	x0, [x28, #G_WIN]
	mov	x2, #0
	SEND	S_toggleFullScreen_
	b	Lret0
Lak_toggle:
	bl	Lact_toggle
	b	Lret0
Lak_back:
	bl	Lact_back
	b	Lret0
Lak_fwd:
	bl	Lact_fwd
	b	Lret0
Lak_up:
	bl	Lact_volup
	b	Lret0
Lak_down:
	bl	Lact_voldown
	b	Lret0
Lak_mute:
	bl	Lact_mute
	b	Lret0

; act_speed(item) — Playback > Speed: This Mac plays at the item's tag / 100, now and after.
	ENTRY	act_speed
	FRAME	3
	mov	x19, x2
	mov	x0, x19
	SEND	S_tag
	mov	x20, x0
	mov	x0, x19                   ; the checkmark moves to it
	SEND	S_menu
	SEND	S_itemArray
	mov	x21, x0
	SEND	S_count
	mov	x22, x0
Lsp_mark:
	subs	x22, x22, #1
	b.lt	Lsp_rate
	mov	x0, x21
	mov	x2, x22
	SEND	S_objectAtIndex_
	cmp	x0, x19
	cset	w2, eq
	SEND	S_setState_
	b	Lsp_mark
Lsp_rate:
	scvtf	s0, w20
	ldr	s1, [x28, #(Lf_100 - G)]
	fdiv	s0, s0, s1
	str	s0, [x28, #G_RATE]
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_setDefaultRate_         ; play uses it from now on
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_timeControlStatus
	cbz	x0, Lret3                 ; paused: it stays paused
	ldr	s0, [x28, #G_RATE]
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_setRate_
	b	Lret3

; media_group(kind) -> This Mac's item's subtitles (0) or sound tracks (1), or nil.
media_group:
	FRAME	1
	CSTR	x9, "AVMediaCharacteristicLegible"
	CSTR	x10, "AVMediaCharacteristicAudible"
	cmp	w0, #0
	csel	x0, x9, x10, eq
	bl	mkstr
	mov	x19, x0
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_currentItem
	SEND	S_asset
	mov	x2, x19
	SEND	S_mediaSelectionGroupForMediaCharacteristic_
	b	Lret1

; act_options(menu) — View > Subtitles and Audio Track as they open: the item's options, the chosen one checked.
	ENTRY	act_options
	FRAME	4
	mov	x19, x2
	mov	x0, x19
	SEND	S_removeAllItems
	ldr	x9, [x28, #G_SUBMENU]
	cmp	x19, x9
	cset	w20, ne                   ; 0: subtitles, 1: sound tracks
	mov	w0, w20
	bl	media_group
	mov	x21, x0
	mov	x22, #0                   ; the chosen option
	cbz	x0, Lop_none
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_currentItem
	SEND	S_currentMediaSelection
	mov	x2, x21
	SEND	S_selectedMediaOptionInMediaSelectionGroup_
	mov	x22, x0
Lop_none:
	CSTR	x1, "Off"                 ; subtitles can be off; a sound track cannot
	CSTR	x9, "Default"
	cmp	x20, #0
	csel	x1, x1, x9, eq
	mov	x0, x19
	ldr	x2, [x27, #S_act_option_]
	GADDR	x3, Ls_slash+1
	bl	add_item
	mov	x23, x0
	mov	x2, #-1
	SEND	S_setTag_
	mov	x0, x23
	cmp	x22, #0
	cset	w2, eq
	SEND	S_setState_
	cbz	x20, Lop_list
	mov	x0, x23                   ; with one sound track there is nothing to choose
	mov	w2, #0
	SEND	S_setEnabled_
Lop_list:
	cbz	x21, Lret4
	mov	x0, x21
	SEND	S_options
	mov	x24, x0
	SEND	S_count
	mov	x25, x0
	mov	x26, #0
Lop_each:
	cmp	x26, x25
	b.hs	Lret4
	mov	x0, x24
	mov	x2, x26
	SEND	S_objectAtIndex_
	mov	x20, x0
	SEND	S_displayName
	SEND	S_UTF8String
	mov	x1, x0
	mov	x0, x19
	ldr	x2, [x27, #S_act_option_]
	GADDR	x3, Ls_slash+1
	bl	add_item
	mov	x23, x0
	mov	x2, x26
	SEND	S_setTag_
	mov	x0, x23
	cmp	x20, x22
	cset	w2, eq
	SEND	S_setState_
	add	x26, x26, #1
	b	Lop_each

; act_option(item) — a subtitle or sound track picked: This Mac's item switches to it (tag -1: subtitles off).
	ENTRY	act_option
	FRAME	2
	mov	x19, x2
	mov	x0, x19
	SEND	S_menu
	ldr	x9, [x28, #G_SUBMENU]
	cmp	x0, x9
	cset	w0, ne
	bl	media_group
	cbz	x0, Lret2
	mov	x20, x0
	mov	x0, x19
	SEND	S_tag
	mov	x21, x0
	mov	x22, #0
	tbnz	x21, #63, Lot_pick
	mov	x0, x20
	SEND	S_options
	mov	x2, x21
	SEND	S_objectAtIndex_
	mov	x22, x0
Lot_pick:
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_currentItem
	mov	x2, x22
	mov	x3, x20
	SEND	S_selectMediaOption_inMediaSelectionGroup_
	b	Lret2

; act_pip — View > Picture in Picture (Opt-Cmd-P): This Mac's picture floats in its own window, and comes back.
	ENTRY	act_pip
	FRAME	1
	ldr	x19, [x28, #G_PIP]
	cbnz	x19, Lpi_toggle
	CLASS	x0, AVPictureInPictureController
	SEND	S_alloc
	mov	x19, x0
	ldr	x0, [x28, #G_VIDEO]
	SEND	S_layer
	mov	x2, x0
	mov	x0, x19
	SEND	S_initWithPlayerLayer_
	mov	x19, x0
	str	x0, [x28, #G_PIP]
	cbz	x0, Lret1
Lpi_toggle:
	mov	x0, x19
	SEND	S_isPictureInPictureActive
	ldr	x9, [x27, #S_startPictureInPicture]
	ldr	x1, [x27, #S_stopPictureInPicture]
	cmp	w0, #0
	csel	x1, x9, x1, eq
	mov	x0, x19
	bl	_objc_msgSend
	b	Lret1

; act_layout — the window was resized (or went full screen).
	ENTRY	act_layout
	b	layout_stage

; act_rescan — Cmd-R: search for devices again (e.g. after changing networks); also the first search.
	ENTRY	act_rescan
	mov	w0, #0
	b	search

; act_scan(menu) — the picker opens: look for devices that came up since, keeping the listed ones in place.
	ENTRY	act_scan
	FRAME	1
	mov	x19, x2
	ldr	x0, [x28, #G_DEV]
	SEND	S_menu
	cmp	x0, x19
	b.ne	Lret1                     ; another menu of the controller's
	mov	w0, #1
	bl	search
	b	Lret1

; search(mode) — start a search unless one of its kind is running.
search:
	mov	w9, #1
	lsl	w9, w9, w0
	add	x11, x28, #G_DISC
	ldsetal	w9, w10, [x11]
	tst	w10, w9
	b.ne	Lse_ret                   ; already running
	mov	x1, x0
	WORKQ
	adr	x2, scan_job
	b	_dispatch_async_f
Lse_ret:
	ret

; imp_yes -> YES: the last window closing quits; the canvas takes the keyboard; a drag is a copy.
imp_yes:
	mov	w0, #1
	ret

; ---- Construction ----

; ---- Entry point ----

; main() — the registry, then services, the app with its menus and window, discovery and the poll timer; then the run loop.
	.globl	_main
_main:
	FRAME	0
	ADDR	x28, G
	ADDR	x27, B
	ADDR	x19, Lreg_names
	BADDR	x20, B_REG
Lmn_reg:
	ldrb	w9, [x19]
	cbz	w9, Lmn_regged
	mov	x0, x19
	BADDR	x9, B_SEL
	cmp	x20, x9
	b.hs	Lmn_sel
	mov	x1, x19
	mov	x0, #-2                   ; RTLD_DEFAULT
	bl	_dlsym
	b	Lmn_store
Lmn_sel:
	bl	_sel_registerName
Lmn_store:
	str	x0, [x20], #8
Lmn_skip:
	ldrb	w9, [x19], #1             ; past the name: nothing is resolved yet
	cbnz	w9, Lmn_skip
	b	Lmn_reg
Lmn_regged:
	mov	w9, #1
	str	w9, [x28, #G_DEVN]        ; the device list starts with This Mac
	BADDR	x10, B_NOW
	str	w9, [x10, #NOW_DEVREV]    ; the first render fills the picker
	fmov	d0, #1.0
	str	d0, [x28, #G_ARTASP]      ; a square card until artwork arrives
	fmov	s0, #1.0
	str	s0, [x28, #G_RATE]
	ldr	x16, [x27, #F_VTIsHardwareDecodeSupported]
	cbz	x16, Lmn_build
	mov	w0, #0x3031               ; 'av01': AV1 streams only where the chip decodes them
	movk	w0, #0x6176, lsl #16
	blr	x16
	and	w0, w0, #0xff
	str	w0, [x28, #G_AV1]
Lmn_build:
	ADDR	x0, Lprog_build
	bl	ui_run
	bl	share_init                ; after curl_global_init, before any other thread
	bl	Lui_refresh
	ADDR	x0, Lprog_show
	bl	ui_run
	bl	layout_stage
	bl	server_start
	cbnz	w0, Lmn_discover
	CSTR	x0, "Could not start the media server."
	mov	w1, #1
	bl	set_status
Lmn_discover:
	bl	Lact_rescan
	ADDR	x0, Lprog_run
	bl	ui_run
	mov	w0, #0
	b	Lret0

; ---- Tables ----

	.section __DATA,__data
	.p2align 3
; UI programs for ui_run.
.macro OP_END
	.byte	0
.endm
.macro STO slot
	.byte	1, (\slot) >> 3
.endm
.macro LD slot
	.byte	2, (\slot) >> 3
.endm
.macro ADDV
	.byte	3
.endm
.macro CLS name
	.byte	4, (C_\name - B_REG) >> 3
.endm
.macro MSG sel, kinds=""
	.byte	6, (\sel - B_SEL) >> 3
	.asciz	"\kinds"
.endm
.macro CALL fn, kinds=""
	.byte	5, (\fn - B_REG) >> 3
	.asciz	"\kinds"
.endm
.macro RC x, top, w, h                ; for 'R': from the content's top-left
	.short	\x, \top, \w, \h
.endm
.macro RN x, y, w, h                  ; for 'N': from the container's bottom-left
	.short	\x, \y, \w, \h
.endm
.macro IMG slot, sym, desc
	CLS	NSImage
	MSG	S_imageWithSystemSymbolName_accessibilityDescription_, "=SS"
	.asciz	"\sym", "\desc"
	STO	\slot
.endm
.macro IMAGE slot, sym, desc
	IMG	\slot, "\sym", "\desc"
	MSG	S_retain, "="
	STO	\slot
.endm
.macro NEWV class, x, top, w, h       ; a new view in the content; it stays current
	CLS	\class
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=R"
	RC	\x, \top, \w, \h
	ADDV
.endm
.macro ADDIN parent                   ; add the current view to a container; it stays current
	STO	G_T3
	LD	\parent
	MSG	S_addSubview_, "O"
	.byte	G_T3 >> 3
	LD	G_T3
.endm
.macro MASKV mask                     ; the current view's autoresizing
	MSG	S_setAutoresizingMask_, "I"
	.byte	\mask
.endm
.macro COLOR slot, r, g, b, a
	CLS	NSColor
	MSG	S_colorWithSRGBRed_green_blue_alpha_, "=KKKK"
	.byte	\r, \g, \b, \a
	MSG	S_retain, "="
	STO	\slot
.endm
.macro LAYERBG color, radius          ; a flat fill with continuous corners for the current view
	MSG	S_setWantsLayer_, "I"
	.byte	1
	STO	G_T3
	LD	\color
	MSG	S_CGColor, "="
	STO	G_T2
	LD	G_T3
	MSG	S_layer, "="
	MSG	S_setBackgroundColor_, "O"
	.byte	G_T2 >> 3
	MSG	S_setCornerRadius_, "D"
	.short	(\radius) * 4
	MSG	S_setCornerCurve_, "S"
	.asciz	"continuous"
	LD	G_T3
.endm
.macro FONT sel, size, weight
	CLS	NSFont
	MSG	\sel, "=DF"
	.short	(\size) * 4
	.byte	\weight
	STO	G_T0
.endm
.macro LABELIN slot, parent, text, x, y, w, h, align, color, mask
	CLS	NSTextField
	MSG	S_labelWithString_, "=S"
	.asciz	"\text"
	STO	\slot
	MSG	S_setFrame_, "N"
	RN	\x, \y, \w, \h
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setTextColor_, "O"
	.byte	\color >> 3
	MSG	S_setAlignment_, "I"
	.byte	\align
	MSG	S_setLineBreakMode_, "I"
	.byte	4                         ; NSLineBreakByTruncatingTail
	MASKV	\mask
	ADDIN	\parent
.endm
.macro SLIDERIN slot, parent, action, x, y, w, max, mask
	CLS	NSSlider
	MSG	S_sliderWithTarget_action_, "=OL"
	.byte	G_CTRL >> 3
	.asciz	"\action"
	STO	\slot
	MSG	S_setControlSize_, "I"
	.byte	1                         ; small: a slim track
	MSG	S_setFrame_, "N"
	RN	\x, \y, \w, SLIDER_H
	MSG	S_setMaxValue_, "D"
	.short	(\max) * 4
	MSG	S_setTrackFillColor_, "O"
	.byte	G_YEL >> 3
	MASKV	\mask
	ADDIN	\parent
.endm
.macro BTN slot, parent, sym, desc, action, tip, x, y, size, pt, mask, tint
	CLS	NSImageSymbolConfiguration
	MSG	S_configurationWithPointSize_weight_, "=DF"
	.short	(\pt) * 4
	.byte	X_SEMIBOLD
	STO	G_T0
	IMG	G_T1, "\sym", "\desc"
	CLS	NSButton
	MSG	S_buttonWithImage_target_action_, "=OOL"
	.byte	G_T1 >> 3, G_CTRL >> 3
	.asciz	"\action"
	STO	\slot
	MSG	S_setBordered_, "I"
	.byte	0
	MSG	S_setSymbolConfiguration_, "O"
	.byte	G_T0 >> 3
	MSG	S_setFrame_, "N"
	RN	\x, \y, \size, \size
	MSG	S_setToolTip_, "S"
	.asciz	"\tip"
	MSG	S_setContentTintColor_, "O"
	.byte	\tint >> 3
	MASKV	\mask
	ADDIN	\parent
.endm
.macro PILL parent, title, action, x, y
	CLS	NSButton
	MSG	S_buttonWithTitle_target_action_, "=SOL"
	.asciz	"\title"
	.byte	G_CTRL >> 3
	.asciz	"\action"
	MSG	S_setBordered_, "I"
	.byte	0
	MSG	S_setFrame_, "N"
	RN	\x, \y, PILL_W, PILL_H
	MSG	S_setContentTintColor_, "O"
	.byte	G_TEXT >> 3
	LAYERBG	G_SURF2, PILL_H / 2
	ADDIN	\parent
.endm
.macro PALETTE slot, sym, color       ; a symbol drawn in one color, kept
	CLS	NSArray
	MSG	S_arrayWithObject_, "=O"
	.byte	\color >> 3
	STO	G_T1
	CLS	NSImageSymbolConfiguration
	MSG	S_configurationWithPaletteColors_, "=O"
	.byte	G_T1 >> 3
	STO	G_T1
	IMG	G_T2, "\sym", "Play on"
	MSG	S_imageWithSymbolConfiguration_, "=O"
	.byte	G_T1 >> 3
	MSG	S_retain, "="
	STO	\slot
.endm
.macro SUBMENU title
	CLS	NSMenu
	MSG	S_alloc, "="
	MSG	S_initWithTitle_, "=S"
	.asciz	"\title"
	STO	G_T1
	LD	G_T0
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SIS"
	.asciz	"\title"
	.byte	0
	.asciz	""
	MSG	S_setSubmenu_, "O"
	.byte	G_T1 >> 3
.endm
.macro ITEM title, action, key
	LD	G_T1
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SLS"
	.asciz	"\title", "\action", "\key"
.endm
.macro NESTED title                   ; a submenu in the current menu (G_T1); it becomes current, in G_T2
	CLS	NSMenu
	MSG	S_alloc, "="
	MSG	S_initWithTitle_, "=S"
	.asciz	"\title"
	STO	G_T2
	LD	G_T1
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SIS"
	.asciz	"\title"
	.byte	0
	.asciz	""
	MSG	S_setSubmenu_, "O"
	.byte	G_T2 >> 3
	LD	G_T2
.endm
.macro SPEED title, percent           ; an item of the Speed submenu (G_T2); it stays current
	LD	G_T2
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SLS"
	.asciz	"\title", "act_speed:", ""
	MSG	S_setTag_, "I"
	.byte	\percent
.endm
.macro MASK flags                     ; the last item's modifiers, when not Command alone
	MSG	S_setKeyEquivalentModifierMask_, "X"
	.long	\flags
.endm
.macro SEP
	CLS	NSMenuItem
	MSG	S_separatorItem, "="
	STO	G_SEP
	LD	G_T1
	MSG	S_addItem_, "O"
	.byte	G_SEP >> 3
.endm

	.equ X_REGULAR,	(F_NSFontWeightRegular - B_REG) >> 3
	.equ X_MEDIUM,	(F_NSFontWeightMedium - B_REG) >> 3
	.equ X_SEMIBOLD,	(F_NSFontWeightSemibold - B_REG) >> 3
	.equ G_SEP,	G_DEV                 ; a separator item, before the picker takes the slot
.macro METHOD name, imp, types="v@:@"    ; - (void)action:(id)sender, unless types say otherwise
	CALL	F_class_addMethod, "OLQC"
	.byte	G_T0 >> 3
	.asciz	"\name"
	.p2align 3
	.quad	\imp
	.asciz	"\types"
.endm

; Services, the colors, the controller (every action's target, the app and window delegate), the canvas, the menus (Edit enables Cmd-V), the window and its views.
Lprog_build:
	CALL	F_objc_autoreleasePoolPush
	CALL	F_signal, "II"            ; a vanished speaker must not kill the app
	.byte	SIGPIPE, SIG_IGN
	CALL	F_curl_global_init, "I"   ; before any other thread exists
	.byte	CURL_GLOBAL_ALL
	CALL	F_dispatch_queue_attr_make_with_qos_class, "=III"
	.byte	0, QOS_CLASS_USER_INITIATED, 0
	CALL	F_dispatch_queue_create, "=CV"  ; the serial device queue
	.asciz	"beam.device"
	STO	G_QUEUE
	CALL	F_dispatch_get_global_queue, "=II"
	.byte	QOS_CLASS_USER_INITIATED, 0
	STO	G_WORKQ
	CALL	F_curl_easy_init, "="     ; its keep-alive handle
	STO	G_CURL
	CALL	F_strlcpy, "BCI"
	.short	B_DEVS
	.asciz	"This Mac"
	.byte	128
	CALL	F_strlcpy, "BCI"
	.short	B_NOW + NOW_NAME
	.asciz	"This Mac"
	.byte	128

	; Flat colors: near-black, two surfaces, one yellow accent.
	COLOR	G_BGC, 21, 21, 21, 255
	COLOR	G_SURF, 28, 28, 28, 240
	COLOR	G_SURF2, 39, 39, 39, 255
	COLOR	G_YEL, 244, 253, 55, 255
	COLOR	G_TEXT, 229, 229, 229, 255
	COLOR	G_SECOND, 160, 160, 160, 255
	COLOR	G_RED, 229, 57, 53, 255

	CLS	NSObject
	CALL	F_objc_allocateClassPair, "=VCI"
	.asciz	"BeamController"
	.byte	0
	STO	G_T0
	METHOD	"act_play:", act_play
	METHOD	"act_toggle:", act_toggle
	METHOD	"act_stop:", act_stop
	METHOD	"act_back:", act_back
	METHOD	"act_fwd:", act_fwd
	METHOD	"act_vol:", act_vol
	METHOD	"act_volup:", act_volup
	METHOD	"act_voldown:", act_voldown
	METHOD	"act_mute:", act_mute
	METHOD	"act_seek:", act_seek
	METHOD	"act_tick:", act_tick
	METHOD	"act_resume:", act_resume
	METHOD	"act_focus:", act_focus
	METHOD	"act_open:", act_open
	METHOD	"act_aonly:", act_aonly
	METHOD	"act_rescan:", act_rescan
	METHOD	"act_device:", act_device
	METHOD	"menuWillOpen:", act_scan
	METHOD	"menuNeedsUpdate:", act_options
	METHOD	"act_speed:", act_speed
	METHOD	"act_option:", act_option
	METHOD	"act_pip:", act_pip
	METHOD	"windowDidResize:", act_layout
	METHOD	"control:textView:doCommandBySelector:", act_urlcmd, "B@:@@:"
	METHOD	"application:openURLs:", act_openurls, "v@:@@"
	METHOD	"applicationShouldTerminateAfterLastWindowClosed:", imp_yes, "B@:@"
	CALL	F_objc_registerClassPair, "O"
	.byte	G_T0 >> 3
	LD	G_T0
	MSG	S_new, "="
	STO	G_CTRL

	; The canvas: the window's content; it takes the keyboard, drops and the mouse.
	CLS	NSView
	CALL	F_objc_allocateClassPair, "=VCI"
	.asciz	"BeamView"
	.byte	0
	STO	G_T0
	METHOD	"acceptsFirstResponder", imp_yes, "B@:"
	METHOD	"mouseMoved:", act_moved
	METHOD	"mouseDown:", act_click
	METHOD	"keyDown:", act_key
	METHOD	"draggingEntered:", imp_yes, "Q@:@"  ; NSDragOperationCopy
	METHOD	"performDragOperation:", act_drop, "B@:@"
	CALL	F_objc_registerClassPair, "O"
	.byte	G_T0 >> 3
	LD	G_T0
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=R"
	RC	0, 0, WIN_W, WIN_H
	STO	G_CONTENT

	CLS	AVPlayer                  ; This Mac's player
	MSG	S_new, "="
	STO	G_PLAYER
	CLS	NSApplication
	MSG	S_sharedApplication, "="
	STO	G_APP
	MSG	S_setActivationPolicy_, "I"
	.byte	0                         ; regular
	MSG	S_setDelegate_, "O"
	.byte	G_CTRL >> 3
	CLS	NSMenu
	MSG	S_new, "="
	STO	G_T0                      ; the menu bar
	LD	G_APP
	MSG	S_setMainMenu_, "O"
	.byte	G_T0 >> 3
	SUBMENU	"Beam"
	ITEM	"About Beam", "orderFrontStandardAboutPanel:", ""
	MASK	0
	SEP
	ITEM	"Hide Beam", "hide:", "h"
	ITEM	"Hide Others", "hideOtherApplications:", "h"
	MASK	0x180000
	ITEM	"Show All", "unhideAllApplications:", ""
	MASK	0
	SEP
	ITEM	"Quit Beam", "terminate:", "q"
	SUBMENU	"File"
	ITEM	"Open\342\200\246", "act_open:", "o"
	ITEM	"Open from URL\342\200\246", "act_focus:", "l"
	SEP
	ITEM	"Close", "performClose:", "w"
	SUBMENU	"Edit"
	ITEM	"Undo", "undo:", "z"
	ITEM	"Redo", "redo:", "z"
	MASK	0x120000
	SEP
	ITEM	"Cut", "cut:", "x"
	ITEM	"Copy", "copy:", "c"
	ITEM	"Paste", "paste:", "v"
	ITEM	"Select All", "selectAll:", "a"
	SUBMENU	"Playback"
	ITEM	"Play/Pause", "act_toggle:", " "  ; Space, only when not typing a link
	MASK	0
	ITEM	"Stop", "act_stop:", "."
	SEP
	ITEM	"Back 10 Seconds", "act_back:", "\357\234\202"
	ITEM	"Forward 10 Seconds", "act_fwd:", "\357\234\203"
	SEP
	ITEM	"Volume Up", "act_volup:", "\357\234\200"
	ITEM	"Volume Down", "act_voldown:", "\357\234\201"
	ITEM	"Mute", "act_mute:", "\357\234\201"
	MASK	0x180000
	SEP
	ITEM	"Audio Only", "act_aonly:", "a"
	MASK	0x180000
	STO	G_AOITEM
	NESTED	"Speed"
	SPEED	"0.5\303\227", 50
	SPEED	"0.75\303\227", 75
	SPEED	"1\303\227", 100
	MSG	S_setState_, "I"          ; normal speed to begin with
	.byte	1
	SPEED	"1.25\303\227", 125
	SPEED	"1.5\303\227", 150
	SPEED	"2\303\227", 200
	SEP
	ITEM	"Find Devices", "act_rescan:", "r"
	SUBMENU	"View"
	ITEM	"Enter Full Screen", "toggleFullScreen:", "f"
	MASK	0x140000
	ITEM	"Picture in Picture", "act_pip:", "p"
	MASK	0x180000
	SEP
	NESTED	"Subtitles"
	STO	G_SUBMENU                 ; the item's legible options; Audio Track lists its audible ones
	MSG	S_setDelegate_, "O"       ; filled as they open
	.byte	G_CTRL >> 3
	NESTED	"Audio Track"
	MSG	S_setDelegate_, "O"
	.byte	G_CTRL >> 3
	SUBMENU	"Window"
	ITEM	"Minimize", "performMiniaturize:", "m"
	ITEM	"Zoom", "performZoom:", ""
	LD	G_APP
	MSG	S_setWindowsMenu_, "O"
	.byte	G_T1 >> 3

	CLS	NSWindow
	MSG	S_alloc, "="
	MSG	S_initWithContentRect_styleMask_backing_defer_, "=RXII"
	RC	0, 0, WIN_W, WIN_H
	.long	WIN_STYLE
	.byte	2, 0                      ; buffered, not deferred
	STO	G_WIN
	MSG	S_setTitle_, "S"          ; for the Window menu and Mission Control
	.asciz	"Beam"
	MSG	S_setTitlebarAppearsTransparent_, "I" ; content flows under it
	.byte	1
	MSG	S_setMovableByWindowBackground_, "I"
	.byte	1
	MSG	S_setTitleVisibility_, "I"
	.byte	1                         ; hidden: the title bar holds only the window buttons
	MSG	S_setBackgroundColor_, "O"
	.byte	G_BGC >> 3
	MSG	S_setCollectionBehavior_, "I"
	.byte	FULL_SCREEN_PRIMARY
	MSG	S_setContentMinSize_, "DD"
	.short	WIN_W * 4, WIN_H * 4
	MSG	S_setDelegate_, "O"
	.byte	G_CTRL >> 3
	MSG	S_setContentView_, "O"
	.byte	G_CONTENT >> 3
	CLS	NSAppearance
	MSG	S_appearanceNamed_, "=S"
	.asciz	"NSAppearanceNameDarkAqua"
	STO	G_T0
	LD	G_WIN
	MSG	S_setAppearance_, "O"
	.byte	G_T0 >> 3
	CLS	NSString                  ; drops: files, links and text
	MSG	S_stringWithUTF8String_, "=C"
	.asciz	"public.file-url public.url public.utf8-plain-text"
	MSG	S_componentsSeparatedByString_, "=S"
	.asciz	" "
	STO	G_T1
	LD	G_CONTENT
	MSG	S_registerForDraggedTypes_, "O"
	.byte	G_T1 >> 3
	CLS	NSTrackingArea            ; mouse moves bring the controls back
	MSG	S_alloc, "="
	MSG	S_initWithRect_options_owner_userInfo_, "=RXOI"
	RC	0, 0, WIN_W, WIN_H
	.long	TRACK_OPTIONS
	.byte	G_CONTENT >> 3, 0
	STO	G_T1
	LD	G_CONTENT
	MSG	S_addTrackingArea_, "O"
	.byte	G_T1 >> 3

	; The picture: This Mac's player, fitted to the window.
	CLS	AVPlayerLayer
	MSG	S_playerLayerWithPlayer_, "=O"
	.byte	G_PLAYER >> 3
	STO	G_T1
	NEWV	NSView, 0, 0, WIN_W, WIN_H
	STO	G_VIDEO
	MSG	S_setLayer_, "O"
	.byte	G_T1 >> 3
	MSG	S_setWantsLayer_, "I"
	.byte	1
	MASKV	AR_WIDTH | AR_HEIGHT
	MSG	S_setHidden_, "I"
	.byte	1

	; The artwork card (placed by layout_stage), with a music note while it has no image.
	CLS	CALayer
	MSG	S_layer, "="
	MSG	S_setContentsGravity_, "S"
	.asciz	"resizeAspectFill"
	STO	G_T0
	NEWV	NSView, 0, 0, 96, 96
	STO	G_ART
	MSG	S_setLayer_, "O"
	.byte	G_T0 >> 3
	MSG	S_setWantsLayer_, "I"
	.byte	1
	MSG	S_setClipsToBounds_, "I"  ; AppKit mirrors it into masksToBounds
	.byte	1
	MSG	S_setHidden_, "I"
	.byte	1
	LAYERBG	G_SURF2, ART_RADIUS
	CLS	NSImageSymbolConfiguration
	MSG	S_configurationWithPointSize_weight_, "=DF"
	.short	56 * 4
	.byte	X_REGULAR
	STO	G_T0
	IMG	G_T2, "music.note", "No artwork"
	CLS	NSImageView
	MSG	S_imageViewWithImage_, "=O"
	.byte	G_T2 >> 3
	STO	G_NOTE
	MSG	S_setSymbolConfiguration_, "O"
	.byte	G_T0 >> 3
	MSG	S_setContentTintColor_, "O"
	.byte	G_SECOND >> 3
	MSG	S_setHidden_, "I"
	.byte	1
	ADDV

	; Nothing playing: an invitation to drop or open something.
	NEWV	NSView, 0, 0, EMPTY_W, EMPTY_H
	STO	G_EMPTY
	CLS	NSImageSymbolConfiguration
	MSG	S_configurationWithPointSize_weight_, "=DF"
	.short	44 * 4
	.byte	X_REGULAR
	STO	G_T0
	IMG	G_T2, "play.circle", ""
	CLS	NSImageView
	MSG	S_imageViewWithImage_, "=O"
	.byte	G_T2 >> 3
	MSG	S_setSymbolConfiguration_, "O"
	.byte	G_T0 >> 3
	MSG	S_setContentTintColor_, "O"
	.byte	G_YEL >> 3
	MSG	S_setFrame_, "N"
	RN	(EMPTY_W - 64) / 2, EMPTY_H - 64, 64, 64
	ADDIN	G_EMPTY
	FONT	S_systemFontOfSize_weight_, 20, X_SEMIBOLD
	LABELIN	G_T2, G_EMPTY, "Drop a file or a link", 0, 88, EMPTY_W, 26, 1, G_TEXT, 0
	FONT	S_systemFontOfSize_weight_, 13, X_REGULAR
	LABELIN	G_T2, G_EMPTY, "Audio and video, from this Mac or the web.", 0, 64, EMPTY_W, 18, 1, G_SECOND, 0
	PILL	G_EMPTY, "Open File\342\200\246", "act_open:", EMPTY_W / 2 - PILL_W - 6, 8
	PILL	G_EMPTY, "Open from URL\342\200\246", "act_focus:", EMPTY_W / 2 + 6, 8

	; A spinner while a link resolves.
	NEWV	NSProgressIndicator, 0, 0, SPIN_S, SPIN_S
	STO	G_SPIN
	MSG	S_setStyle_, "I"
	.byte	1                         ; spinning
	MSG	S_setDisplayedWhenStopped_, "I"
	.byte	0

	; Status line under the title bar: errors in red, hints in grey.
	CLS	NSTextField
	MSG	S_labelWithString_, "=S"
	.asciz	""
	STO	G_STATUS
	MSG	S_setFrame_, "R"
	RC	80, STATUS_T, WIN_W - 160, LABEL_H
	FONT	S_systemFontOfSize_weight_, 12, X_REGULAR
	LD	G_STATUS
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setAlignment_, "I"
	.byte	1                         ; centered
	MSG	S_setLineBreakMode_, "I"
	.byte	4
	MASKV	AR_WIDTH | AR_BOTTOM
	ADDV

	; The control bar, floating at the bottom: progress, then the track, the transport, the sound and where it plays.
	NEWV	NSView, BAR_M, WIN_H - BAR_M - BAR_H, BAR_W, BAR_H
	STO	G_BAR
	MASKV	AR_WIDTH | AR_TOP
	LAYERBG	G_SURF, 16
	FONT	S_monospacedDigitSystemFontOfSize_weight_, 11, X_MEDIUM
	LABELIN	G_CUR, G_BAR, "0:00", 16, ROW1_Y + 2, TIME_W, LABEL_H, 0, G_SECOND, AR_RIGHT
	LABELIN	G_DUR, G_BAR, "--:--", BAR_W - 16 - TIME_W, ROW1_Y + 2, TIME_W, LABEL_H, 2, G_SECOND, AR_LEFT
	SLIDERIN	G_POS, G_BAR, "act_seek:", 24 + TIME_W, ROW1_Y, BAR_W - 2 * (24 + TIME_W), 1, AR_WIDTH
	FONT	S_systemFontOfSize_weight_, 13, X_SEMIBOLD
	LABELIN	G_TITLE, G_BAR, "Nothing playing", 16, ROW2_C - 9, TEXT_W, 18, 0, G_SECOND, AR_WIDTH | AR_RIGHT
	FONT	S_systemFontOfSize_weight_, 12, X_REGULAR
	LABELIN	G_ARTIST, G_BAR, "", 16, ROW2_C - 17, TEXT_W, 16, 0, G_SECOND, AR_WIDTH | AR_RIGHT
	BTN	G_BACK, G_BAR, "gobackward.10", "Back 10 seconds", "act_back:", "Back 10 seconds (\342\214\230\342\206\220)", BACK_X, ROW2_C - BTN_S / 2, BTN_S, 16, AR_LEFT | AR_RIGHT, G_TEXT
	BTN	G_PP, G_BAR, "play.fill", "Play or pause", "act_toggle:", "Play or pause (Space)", PLAY_X, ROW2_C - PLAY_S / 2, PLAY_S, 17, AR_LEFT | AR_RIGHT, G_BGC
	LAYERBG	G_YEL, PLAY_S / 2
	BTN	G_FWD, G_BAR, "goforward.10", "Forward 10 seconds", "act_fwd:", "Forward 10 seconds (\342\214\230\342\206\222)", FWD_X, ROW2_C - BTN_S / 2, BTN_S, 16, AR_LEFT | AR_RIGHT, G_TEXT
	BTN	G_AOBTN, G_BAR, "headphones", "Audio only", "act_aonly:", "Audio Only (\342\214\245\342\214\230A)", AO_X, ROW2_C - ICON_S / 2, ICON_S, 13, AR_LEFT, G_SECOND
	BTN	G_MUTE, G_BAR, "speaker.wave.2.fill", "Mute", "act_mute:", "Mute (\342\214\245\342\214\230\342\206\223)", MUTE_X, ROW2_C - ICON_S / 2, ICON_S, 13, AR_LEFT, G_SECOND
	SLIDERIN	G_VOL, G_BAR, "act_vol:", VOL_X, ROW2_C - SLIDER_H / 2, VOL_W, 100, AR_LEFT

	; AirPlay: This Mac's picture and sound to an Apple TV or an AirPlay TV or speaker; lit while it does.
	CLS	AVRoutePickerView
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=N"
	RN	AIR_X, ROW2_C - AIR_W / 2, AIR_W, AIR_W
	MSG	S_setPlayer_, "O"
	.byte	G_PLAYER >> 3
	MSG	S_setRoutePickerButtonBordered_, "I"
	.byte	0
	MSG	S_setRoutePickerButtonColor_forState_, "OI"
	.byte	G_SECOND >> 3, 0          ; normal
	MSG	S_setRoutePickerButtonColor_forState_, "OI"
	.byte	G_YEL >> 3, 2             ; active
	MSG	S_setToolTip_, "S"
	.asciz	"AirPlay"
	MASKV	AR_LEFT
	ADDIN	G_BAR

	; Where it plays: This Mac or a network speaker or TV, a pull-down whose face is lit while a device plays.
	PALETTE	G_IMGDEV, "hifispeaker.2.fill", G_TEXT
	PALETTE	G_IMGDEVON, "hifispeaker.2.fill", G_YEL
	CLS	NSPopUpButton
	MSG	S_alloc, "="
	MSG	S_initWithFrame_pullsDown_, "=NI"
	RN	DEV_X, ROW2_C - 14, DEV_W, 28
	.byte	1
	STO	G_DEV
	MSG	S_setBordered_, "I"
	.byte	0
	MSG	S_setTarget_, "O"
	.byte	G_CTRL >> 3
	MSG	S_setAction_, "L"
	.asciz	"act_device:"
	MSG	S_setToolTip_, "S"
	.asciz	"Play on a network speaker or TV"
	MASKV	AR_LEFT
	ADDIN	G_BAR
	MSG	S_cell, "="
	MSG	S_setArrowPosition_, "I"
	.byte	0                         ; no arrow: the icon says it all
	LD	G_DEV
	MSG	S_menu, "="               ; its opening starts a search
	MSG	S_setDelegate_, "O"
	.byte	G_CTRL >> 3
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SIS"
	.asciz	""
	.byte	0
	.asciz	""
	MSG	S_setImage_, "O"          ; the face
	.byte	G_IMGDEV >> 3

	; Open from URL: a field floating under the title bar.
	NEWV	NSView, (WIN_W - URL_W) / 2, 56, URL_W, URL_H
	STO	G_URLBOX
	MASKV	AR_LEFT | AR_RIGHT | AR_BOTTOM
	LAYERBG	G_SURF2, 12
	MSG	S_setHidden_, "I"
	.byte	1
	IMG	G_T1, "link", "Link"
	CLS	NSImageView
	MSG	S_imageViewWithImage_, "=O"
	.byte	G_T1 >> 3
	MSG	S_setFrame_, "N"
	RN	16, 14, 20, 20
	MSG	S_setContentTintColor_, "O"
	.byte	G_SECOND >> 3
	ADDIN	G_URLBOX
	FONT	S_systemFontOfSize_weight_, 17, X_REGULAR
	CLS	NSTextField
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=N"
	RN	46, 12, URL_W - 62, 24
	STO	G_FIELD
	MSG	S_setBezeled_, "I"
	.byte	0
	MSG	S_setDrawsBackground_, "I"
	.byte	0
	MSG	S_setFocusRingType_, "I"
	.byte	1                         ; none: the caret shows focus
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setTextColor_, "O"
	.byte	G_TEXT >> 3
	MSG	S_setPlaceholderString_, "S"
	.asciz	"Paste a link or search YouTube"
	MSG	S_setTarget_, "O"
	.byte	G_CTRL >> 3
	MSG	S_setAction_, "L"
	.asciz	"act_play:"
	MSG	S_setDelegate_, "O"       ; Escape closes it
	.byte	G_CTRL >> 3
	ADDIN	G_URLBOX
	MSG	S_cell, "="
	MSG	S_setScrollable_, "I"     ; one line that scrolls, however long the link
	.byte	1
	MSG	S_setUsesSingleLineMode_, "I"
	.byte	1

	; Images swapped by ui_refresh.
	IMAGE	G_IMGPLAY, "play.fill", "Play"
	IMAGE	G_IMGPAUSE, "pause.fill", "Pause"
	IMAGE	G_IMGMUTED, "speaker.slash.fill", "Unmute"
	IMAGE	G_IMGUNMUTED, "speaker.wave.2.fill", "Mute"
	OP_END

; The first size, centered; neither is saved, so the app writes no preferences.
Lprog_show:
	LD	G_WIN
	MSG	S_setContentSize_, "DD"
	.short	START_W * 4, START_H * 4
	MSG	S_center
	MSG	S_makeKeyAndOrderFront_, "I"
	.byte	0
	MSG	S_makeFirstResponder_, "O"
	.byte	G_CONTENT >> 3
	OP_END

; While a link resolves the spinner turns; then it rests.
Lprog_busy:
	LD	G_SPIN
	MSG	S_startAnimation_, "I"
	.byte	0
	OP_END
Lprog_idle:
	LD	G_SPIN
	MSG	S_stopAnimation_, "I"
	.byte	0
	OP_END

; Played: the link field empties.
Lprog_played:
	LD	G_FIELD
	MSG	S_setStringValue_, "S"
	.asciz	""
	OP_END

; Open from URL: the window forward, the field shown and focused with its text selected.
Lprog_focus:
	LD	G_URLBOX
	MSG	S_setHidden_, "I"
	.byte	0
	LD	G_WIN
	MSG	S_makeKeyAndOrderFront_, "I"
	.byte	0
	LD	G_FIELD
	MSG	S_selectText_, "I"
	.byte	0
	OP_END

; The field goes away and the canvas keeps the keyboard.
Lprog_urlhide:
	LD	G_URLBOX
	MSG	S_setHidden_, "I"
	.byte	1
	LD	G_WIN
	MSG	S_makeFirstResponder_, "O"
	.byte	G_CONTENT >> 3
	OP_END

; Audio Only's swap: a quarter-second timer until the new item is ready.
Lprog_resume:
	CLS	NSTimer
	MSG	S_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_, "=DOLII"
	.short	1
	.byte	G_CTRL >> 3
	.asciz	"act_resume:"
	.byte	0, 1
	STO	G_RESUMET
	OP_END

; The 1 Hz poll timer (macOS may coalesce its wakeups), then the run loop.
Lprog_run:
	CLS	NSTimer
	MSG	S_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_, "=DOLII"
	.short	4
	.byte	G_CTRL >> 3
	.asciz	"act_tick:"
	.byte	0, 1
	MSG	S_setTolerance_, "D"
	.short	1
	LD	G_APP
	MSG	S_activate
	MSG	S_run
	OP_END

; InnerTube endpoints: URL, then the field mask (it cuts a player response from ~183 KB to ~69 KB).
Lep_guide:	.asciz	"https://www.youtube.com/youtubei/v1/guide?prettyPrint=false", "X-Goog-FieldMask: responseContext.visitorData"
Lep_search:	.asciz	"https://www.youtube.com/youtubei/v1/search?prettyPrint=false", "X-Goog-FieldMask: contents,responseContext.visitorData"
Lep_player:	.asciz	"https://www.youtube.com/youtubei/v1/player?prettyPrint=false", "X-Goog-FieldMask: streamingData,videoDetails,playabilityStatus,responseContext.visitorData"

; Headers of every InnerTube request.
Lapi_headers:
	.asciz	"Content-Type: application/json"
	.asciz	"Origin: https://www.youtube.com"
	.asciz	"Accept-Language: en-US,en;q=0.9"
	.asciz	"Connection: keep-alive"
	.asciz	"Accept:"
	.asciz	"Expect:"
	.byte	0

; InnerTube clients: User-Agent, context fields, headers. The player chain is tried in order: VISIONOS URLs serve whole streams, the rest cover what it refuses.
Lclients:
	.short	Lcl2 - Lclients
	.asciz	"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
	.asciz	"\"clientName\":\"VISIONOS\",\"clientVersion\":\"1.02\",\"osName\":\"visionOS\",\"osVersion\":\"26.5.23O471\",\"deviceModel\":\"RealityDevice17,1\",\"deviceMake\":\"Apple\","
	.asciz	"X-YouTube-Client-Name: 101"
	.asciz	"X-YouTube-Client-Version: 1.02"
	.byte	0
Lcl2:
	.short	Lcl3 - Lcl2
	.asciz	"com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; en_US) gzip"
	.asciz	"\"clientName\":\"ANDROID_VR\",\"clientVersion\":\"1.65.10\",\"osName\":\"Android\",\"osVersion\":\"12L\",\"deviceModel\":\"Quest 3\",\"androidSdkVersion\":32,"
	.asciz	"X-YouTube-Client-Name: 28"
	.asciz	"X-YouTube-Client-Version: 1.65.10"
	.byte	0
Lcl3:
	.short	Lcl4 - Lcl3
Lc_android:	                          ; also the search client
	.asciz	"com.google.android.youtube/20.10.38 (Linux; U; Android 14; en_US) gzip"
	.asciz	"\"clientName\":\"ANDROID\",\"clientVersion\":\"20.10.38\",\"osName\":\"Android\",\"osVersion\":\"14\",\"androidSdkVersion\":34,"
	.asciz	"X-YouTube-Client-Name: 3"
	.asciz	"X-YouTube-Client-Version: 20.10.38"
	.byte	0
Lcl4:
	.short	Lcl5 - Lcl4
	.asciz	"com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X; en_US)"
	.asciz	"\"clientName\":\"IOS\",\"clientVersion\":\"20.10.4\",\"osName\":\"iOS\",\"osVersion\":\"18.3.2.22D82\",\"deviceModel\":\"iPhone16,2\","
	.asciz	"X-YouTube-Client-Name: 5"
	.asciz	"X-YouTube-Client-Version: 20.10.4"
	.byte	0
Lcl5:
	.short	0
Lc_web:	                                  ; the visitorData client
	.asciz	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
	.asciz	"\"clientName\":\"WEB\",\"clientVersion\":\"2.20260114.08.00\",\"osName\":\"Windows\",\"osVersion\":\"10.0\","
	.asciz	"X-YouTube-Client-Name: 1"
	.asciz	"X-YouTube-Client-Version: 2.20260114.08.00"
	.byte	0

; The registry's names, in its order.
.macro REG sym, name
	.asciz	"\name"
.endm
.macro REGSEL
.endm
.macro FN name
	.asciz	"\name"
.endm
Lreg_names:
	REGISTRY
	.byte	0

	.section __DATA,__objc_imageinfo,regular,no_dead_strip
	.long	0
	.long	64
