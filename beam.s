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

; CSTR reg, text — a C string literal, kept after G.
.macro CSTR reg, text
	.pushsection __DATA,__data
Lc\@:	.asciz	"\text"
	.popsection
	GADDR	\reg, Lc\@
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
.equ LIVE_TRIES,                 3        ; failed segment fetches in a row before a live stream ends
.equ SLOTS,                      8
.equ TOKEN_STRIDE,               40       ; 32 hex + NUL; the last byte flags a live stream
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

; Play job: main -> worker -> device queue -> main.
.equ JOB_QUERY,                  0        ; char*, link or search text (owned)
.equ JOB_RESULT,                 8        ; int, PLAY_*
.equ JOB_LIVE,                   12       ; int
.equ JOB_DUR,                    16       ; seconds, 0 when live
.equ JOB_ERR,                    24       ; char*, why it failed, or NULL
.equ JOB_TRACK,                  32       ; Track
.equ JOB_LOCAL,                  JOB_TRACK + T_SIZE ; char[256], This Mac's stream URL of a live broadcast
.equ JOB_MSG,                    JOB_LOCAL + 256    ; char[128], an error message
.equ JOB_URL,                    JOB_MSG + 128      ; char[4096], the media URL
.equ JOB_SIZE,                   JOB_URL + 4096
.equ PLAY_OK,                    0
.equ PLAY_FAILED,                1
.equ PLAY_REJECTED,              2

; Device list entries; entry 0 is This Mac.
.equ DEV_NAME,                   0
.equ DEV_BASE,                   128
.equ DEV_AVT,                    256
.equ DEV_RC,                     512
.equ DEV_SIZE,                   768
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
.equ WIN_STYLE,                  0x8007   ; titled|closable|miniaturizable|fullSizeContentView
.equ NSEventTypeLeftMouseDown,   1
.equ NSEventTypeLeftMouseDragged, 6

; Window layout in points from the top-left of the content.
.equ WIN_W,                      360
.equ WIN_H,                      696
.equ PAD,                        28
.equ CONTENT_W,                  WIN_W - 2 * PAD
.equ FIELD_T,                    52
.equ FIELD_H,                    28
.equ ART_T,                      104
.equ ART_S,                      232
.equ ART_X,                      (WIN_W - ART_S) / 2
.equ ART_RADIUS,                 16
.equ SPIN_S,                     32
.equ TITLE_T,                    356
.equ TEXT_BAND,                  66
.equ TEXT_GAP,                   4
.equ TITLE_MAX_H,                44
.equ ARTIST_H,                   18
.equ SEEK_T,                     440
.equ TIME_T,                     464
.equ TIME_W,                     64
.equ LABEL_H,                    16
.equ SLIDER_H,                   20
.equ PLAY_T,                     496
.equ PLAY_S,                     60
.equ BTN_S,                      44
.equ BTN_GAP,                    32
.equ PLAY_X,                     (WIN_W - PLAY_S) / 2
.equ BACK_X,                     PLAY_X - BTN_GAP - BTN_S
.equ FWD_X,                      PLAY_X + PLAY_S + BTN_GAP
.equ SMALL_T,                    PLAY_T + (PLAY_S - BTN_S) / 2
.equ VOL_T,                      580
.equ VOL_ICON_S,                 22
.equ VOL_X,                      PAD + VOL_ICON_S + 8
.equ VOL_W,                      CONTENT_W - 2 * (VOL_ICON_S + 8)
.equ VMAX_X,                     WIN_W - PAD - VOL_ICON_S
.equ DEV_T,                      620
.equ DEV_H,                      24
.equ STATUS_T,                   660
.equ PICKER_AIR,                 4

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
.equ G_WIN,                      184      ; views and images (main thread)
.equ G_CONTENT,                  192
.equ G_FIELD,                    200
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
.equ G_BGART,                    304
.equ G_STATUS,                   312
.equ G_DEV,                      320
.equ G_IMGPLAY,                  328
.equ G_IMGPAUSE,                 336
.equ G_IMGMUTED,                 344
.equ G_IMGUNMUTED,               352
.equ G_SLOTURL,                  360      ; char*[SLOTS], media URLs (lock)
.equ G_SECOND,                   424      ; the secondary label color (main)
.equ G_T0,                       432      ; scratch objects of the UI programs
.equ G_T1,                       440
.equ G_T2,                       448
.equ G_WORKQ,                    456      ; the global user-initiated queue
.equ G_SIZE,                     464

; ---- Data ----

	.section __DATA,__data
	.p2align 3
G:	.space	G_SIZE
	.if (CONTENT_W != 304) || (PICKER_AIR != 4) || (DEV_H != 24) || (WIN_W != 360) || (WIN_H - DEV_T - DEV_H != 52)
	.error "the UI doubles below follow the layout"
	.endif
Ld_cw:	.double	304.0                     ; CONTENT_W: UI doubles, 8-aligned after G
Ld_1000:	.double	1000.0
Ld_air:	.double	1004.0                    ; 1000 + PICKER_AIR
Ld_devh:	.double	24.0                      ; DEV_H
Ld_winw:	.double	360.0                     ; WIN_W
Ld_devy:	.double	52.0                      ; WIN_H - DEV_T - DEV_H
Lf_100:	.float	100.0                     ; volume percent
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
.equ B_NOW,                      784      ; snapshot (lock)
.equ B_MYURI,                    3776     ; char[256], what we last sent to the device (device queue)
.equ B_MYTRACK,                  4096     ; and its track
.equ B_SLOTTOK,                  6912     ; stream tokens (lock)
.equ B_UIMSG,                    7232     ; char[256], status message (main)
.equ B_UIWTITLE,                 7488     ; char[128], last rendered window title (main)
.equ B_UIARTIST,                 7616     ; char[256], last rendered artist (main)
.equ B_UIART,                    8192     ; char[2048], artwork shown or loading (main)
.equ B_UITITLE,                  10240    ; char[512], last rendered title (main)
.equ B_LTTRACK,                  12288    ; This Mac's track (main)
.equ B_DEVS,                     16384    ; device list (lock)
.equ B_REG,                      B_DEVS + MAX_DEVS * DEV_SIZE ; the registry

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
	FN	curl_slist_append
	FN	curl_slist_free_all
	FN	dispatch_async_f
	FN	dispatch_sync_f
	FN	free
	FN	freeifaddrs
	FN	getenv
	FN	getifaddrs
	FN	getsockname
	FN	inet_ntop
	FN	listen
	FN	malloc
	FN	memcpy
	FN	objc_autoreleasePoolPop
	FN	objc_autoreleasePoolPush
	FN	objc_msgSend
	FN	os_unfair_lock_lock
	FN	os_unfair_lock_unlock
	FN	pthread_create
	FN	pthread_detach
	FN	realloc
	FN	recv
	FN	sel_registerName
	FN	sendto
	FN	setsockopt
	FN	snprintf
	FN	socket
	FN	sscanf
	FN	strcasestr
	FN	strchr
	FN	strcmp
	FN	strcspn
	FN	strdup
	FN	strlcpy
	FN	strlen
	FN	strncmp
	FN	strstr
	FN	strtol
	FN	usleep
	FN	write
	SYM	NSFontAttributeName
	SYM	NSFontWeightMedium
	SYM	NSFontWeightRegular
	SYM	NSFontWeightSemibold
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
	OBJC	CALayer
	OBJC	NSAppearance
	OBJC	NSApplication
	OBJC	NSBox
	OBJC	NSButton
	OBJC	NSCharacterSet
	OBJC	NSColor
	OBJC	NSData
	OBJC	NSDictionary
	OBJC	NSFont
	OBJC	NSImage
	OBJC	NSImageSymbolConfiguration
	OBJC	NSImageView
	OBJC	NSJSONSerialization
	OBJC	NSMenu
	OBJC	NSMenuItem
	OBJC	NSObject
	OBJC	NSPopUpButton
	OBJC	NSProgressIndicator
	OBJC	NSSearchField
	OBJC	NSSlider
	OBJC	NSString
	OBJC	NSTextField
	OBJC	NSTimer
	OBJC	NSURL
	OBJC	NSView
	OBJC	NSVisualEffectView
	OBJC	NSWindow
	REGSEL
	REG	S_systemFontOfSize_weight_, "systemFontOfSize:weight:"
	REG	S_monospacedDigitSystemFontOfSize_weight_, "monospacedDigitSystemFontOfSize:weight:"
	REG	S_JSONObjectWithData_options_error_, "JSONObjectWithData:options:error:"
	REG	S_URLWithString_, "URLWithString:"
	REG	S_UTF8String, "UTF8String"
	REG	S_activate, "activate"
	REG	S_addItem_, "addItem:"
	REG	S_addItemWithTitle_action_keyEquivalent_, "addItemWithTitle:action:keyEquivalent:"
	REG	S_addSubview_, "addSubview:"
	REG	S_alloc, "alloc"
	REG	S_appearanceNamed_, "appearanceNamed:"
	REG	S_buttonWithImage_target_action_, "buttonWithImage:target:action:"
	REG	S_cell, "cell"
	REG	S_center, "center"
	REG	S_configurationWithPointSize_weight_, "configurationWithPointSize:weight:"
	REG	S_contentView, "contentView"
	REG	S_currentEvent, "currentEvent"
	REG	S_currentItem, "currentItem"
	REG	S_currentTime, "currentTime"
	REG	S_dataWithBytes_length_, "dataWithBytes:length:"
	REG	S_dataWithBytesNoCopy_length_freeWhenDone_, "dataWithBytesNoCopy:length:freeWhenDone:"
	REG	S_dictionaryWithObject_forKey_, "dictionaryWithObject:forKey:"
	REG	S_doubleValue, "doubleValue"
	REG	S_font, "font"
	REG	S_imageViewWithImage_, "imageViewWithImage:"
	REG	S_imageWithSystemSymbolName_accessibilityDescription_, "imageWithSystemSymbolName:accessibilityDescription:"
	REG	S_indexOfSelectedItem, "indexOfSelectedItem"
	REG	S_initWithContentRect_styleMask_backing_defer_, "initWithContentRect:styleMask:backing:defer:"
	REG	S_initWithData_, "initWithData:"
	REG	S_initWithFrame_, "initWithFrame:"
	REG	S_initWithTitle_, "initWithTitle:"
	REG	S_intValue, "intValue"
	REG	S_isEnabled, "isEnabled"
	REG	S_isMuted, "isMuted"
	REG	S_itemTitleAtIndex_, "itemTitleAtIndex:"
	REG	S_labelColor, "labelColor"
	REG	S_labelWithString_, "labelWithString:"
	REG	S_layer, "layer"
	REG	S_makeFirstResponder_, "makeFirstResponder:"
	REG	S_makeKeyAndOrderFront_, "makeKeyAndOrderFront:"
	REG	S_maxValue, "maxValue"
	REG	S_menu, "menu"
	REG	S_new, "new"
	REG	S_numberOfItems, "numberOfItems"
	REG	S_pause, "pause"
	REG	S_play, "play"
	REG	S_playerItemWithURL_, "playerItemWithURL:"
	REG	S_quaternarySystemFillColor, "quaternarySystemFillColor"
	REG	S_removeItemAtIndex_, "removeItemAtIndex:"
	REG	S_replaceCurrentItemWithPlayerItem_, "replaceCurrentItemWithPlayerItem:"
	REG	S_release, "release"
	REG	S_retain, "retain"
	REG	S_run, "run"
	REG	S_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_, "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"
	REG	S_secondaryLabelColor, "secondaryLabelColor"
	REG	S_seekToTime_, "seekToTime:"
	REG	S_selectItemAtIndex_, "selectItemAtIndex:"
	REG	S_selectText_, "selectText:"
	REG	S_separatorItem, "separatorItem"
	REG	S_setAction_, "setAction:"
	REG	S_setActivationPolicy_, "setActivationPolicy:"
	REG	S_setAlignment_, "setAlignment:"
	REG	S_setAppearance_, "setAppearance:"
	REG	S_setBlendingMode_, "setBlendingMode:"
	REG	S_setBorderWidth_, "setBorderWidth:"
	REG	S_setBordered_, "setBordered:"
	REG	S_setBoxType_, "setBoxType:"
	REG	S_setClipsToBounds_, "setClipsToBounds:"
	REG	S_setContentTintColor_, "setContentTintColor:"
	REG	S_setContentView_, "setContentView:"
	REG	S_setContents_, "setContents:"
	REG	S_setContentsGravity_, "setContentsGravity:"
	REG	S_setContentsRect_, "setContentsRect:"
	REG	S_setControlSize_, "setControlSize:"
	REG	S_setCornerCurve_, "setCornerCurve:"
	REG	S_setCornerRadius_, "setCornerRadius:"
	REG	S_setDelegate_, "setDelegate:"
	REG	S_setDisplayedWhenStopped_, "setDisplayedWhenStopped:"
	REG	S_setDoubleValue_, "setDoubleValue:"
	REG	S_setEnabled_, "setEnabled:"
	REG	S_setFillColor_, "setFillColor:"
	REG	S_setFocusRingType_, "setFocusRingType:"
	REG	S_setFont_, "setFont:"
	REG	S_setFrame_, "setFrame:"
	REG	S_setHidden_, "setHidden:"
	REG	S_setImage_, "setImage:"
	REG	S_setKeyEquivalentModifierMask_, "setKeyEquivalentModifierMask:"
	REG	S_setLayer_, "setLayer:"
	REG	S_setLineBreakMode_, "setLineBreakMode:"
	REG	S_setMainMenu_, "setMainMenu:"
	REG	S_setMaterial_, "setMaterial:"
	REG	S_setMaxValue_, "setMaxValue:"
	REG	S_setMaximumNumberOfLines_, "setMaximumNumberOfLines:"
	REG	S_setMovableByWindowBackground_, "setMovableByWindowBackground:"
	REG	S_setMuted_, "setMuted:"
	REG	S_setPlaceholderString_, "setPlaceholderString:"
	REG	S_setSelectable_, "setSelectable:"
	REG	S_setSendsWholeSearchString_, "setSendsWholeSearchString:"
	REG	S_setState_, "setState:"
	REG	S_setStringValue_, "setStringValue:"
	REG	S_setStyle_, "setStyle:"
	REG	S_setSubmenu_, "setSubmenu:"
	REG	S_setSymbolConfiguration_, "setSymbolConfiguration:"
	REG	S_setTarget_, "setTarget:"
	REG	S_setTextColor_, "setTextColor:"
	REG	S_setTitle_, "setTitle:"
	REG	S_setTitlePosition_, "setTitlePosition:"
	REG	S_setTitleVisibility_, "setTitleVisibility:"
	REG	S_setTitlebarAppearsTransparent_, "setTitlebarAppearsTransparent:"
	REG	S_setTolerance_, "setTolerance:"
	REG	S_setToolTip_, "setToolTip:"
	REG	S_setTruncatesLastVisibleLine_, "setTruncatesLastVisibleLine:"
	REG	S_setVolume_, "setVolume:"
	REG	S_setWantsLayer_, "setWantsLayer:"
	REG	S_setWindowsMenu_, "setWindowsMenu:"
	REG	S_sharedApplication, "sharedApplication"
	REG	S_size, "size"
	REG	S_sizeThatFits_, "sizeThatFits:"
	REG	S_sizeWithAttributes_, "sizeWithAttributes:"
	REG	S_sliderWithTarget_action_, "sliderWithTarget:action:"
	REG	S_startAnimation_, "startAnimation:"
	REG	S_stopAnimation_, "stopAnimation:"
	REG	S_stringByTrimmingCharactersInSet_, "stringByTrimmingCharactersInSet:"
	REG	S_stringValue, "stringValue"
	REG	S_stringWithUTF8String_, "stringWithUTF8String:"
	REG	S_systemRedColor, "systemRedColor"
	REG	S_tertiaryLabelColor, "tertiaryLabelColor"
	REG	S_timeControlStatus, "timeControlStatus"
	REG	S_titleOfSelectedItem, "titleOfSelectedItem"
	REG	S_titleRectForBounds_, "titleRectForBounds:"
	REG	S_type, "type"
	REG	S_volume, "volume"
	REG	S_whitespaceAndNewlineCharacterSet, "whitespaceAndNewlineCharacterSet"
	REG	S_wrappingLabelWithString_, "wrappingLabelWithString:"
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
.equ B_SIZE,                     B_SCAN + 2 * SC_SIZE
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
Ls_range:	.asciz	"%lld-%lld"
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
	FRAME	3, 144
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

; play_resolve(job) — resolve the link, hand it to the device or to This Mac, report to main.
	ENTRY	play_resolve
	FRAME	1
	mov	x19, x0
	bl	resolve
	str	w0, [x19, #JOB_RESULT]
	cbnz	w0, Lpr_done
	LOCK
	BADDR	x9, B_NOW
	ldr	w20, [x9, #NOW_SEL]
	UNLOCK
	cbnz	w20, Lpr_device
	ldr	w9, [x19, #JOB_LIVE]
	cbz	w9, Lpr_done              ; This Mac plays the media URL itself
	mov	x0, x19                   ; a live broadcast goes through the proxy, as AAC
	CSTR	x1, "127.0.0.1"
	add	x2, x19, #JOB_LOCAL
	bl	stream_uri
	b	Lpr_done
Lpr_device:
	ldr	x0, [x28, #G_QUEUE]
	mov	x1, x19
	adr	x2, play_upnp
	bl	_dispatch_sync_f          ; keeps the job alive until the device answers
Lpr_done:
	adr	x0, ui_play_done
	mov	x1, x19
	bl	post_main
	b	Lret1

; stream_uri(job, host, out[256]) — serve the job's media under a fresh random token; out = its URL on host.
stream_uri:
	FRAME	3, 96
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	mov	x0, sp                    ; 128 random bits, printed as 32 hex digits
	mov	x1, #16
	bl	_arc4random_buf
	add	x0, sp, #48
	mov	x1, #TOKEN_STRIDE
	CSTR	x2, "%016llx%016llx"
	bl	_snprintf
	ldr	w22, [x19, #JOB_LIVE]
	strb	w22, [sp, #(48 + TOKEN_STRIDE - 1)] ; a slot's last byte flags a live broadcast
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
	add	x0, x19, #JOB_URL
	bl	_strdup
	str	x0, [x24, x23, lsl #3]
	UNLOCK
	ldr	w9, [x28, #G_PORT]
	stp	x20, x9, [sp]
	CSTR	x10, "m4a"
	CSTR	x11, "aac"
	cmp	w22, #0
	csel	x10, x10, x11, eq
	add	x9, sp, #48
	stp	x9, x10, [sp, #16]
	mov	x0, x21
	mov	x1, #256
	CSTR	x2, "http://%s:%u/stream/%s.%s"
	bl	_snprintf
	b	Lret3

; play_upnp(job) — serve the media and play it on the device with DIDL-Lite metadata.
	ENTRY	play_upnp
	FRAME	3, 48
	mov	x19, x0
	BADDR	x1, B_LANIP
	BADDR	x2, B_MYURI
	bl	stream_uri
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
	stp	x20, x21, [sp]
	ldr	w9, [x19, #JOB_LIVE]
	GADDR	x10, Ls_mp4
	GADDR	x11, Ls_aac
	cmp	w9, #0
	csel	x10, x10, x11, eq
	stp	x22, x10, [sp, #16]
	BADDR	x9, B_MYURI
	str	x9, [sp, #32]
	add	x0, sp, #40
	CSTR	x1, "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\"><item id=\"-1\" parentID=\"-1\" restricted=\"true\"><dc:title>%s</dc:title><dc:creator>%s</dc:creator><upnp:albumArtURI>%s</upnp:albumArtURI><upnp:class>object.item.audioItem.musicTrack</upnp:class><res protocolInfo=\"http-get:*:%s:*\">%s</res></item></DIDL-Lite>"
	bl	_asprintf
	mov	x0, x20
	bl	_free
	mov	x0, x21
	bl	_free
	mov	x0, x22
	bl	_free
	mov	w22, #PLAY_REJECTED
	ldr	x20, [sp, #40]
	cbz	x20, Lps_done
	mov	x0, x20
	bl	xml_escape                ; the DIDL travels as text inside SOAP
	mov	x21, x0
	mov	x0, x20
	bl	_free
	cbz	x21, Lps_done
	BADDR	x9, B_MYURI
	stp	x9, x21, [sp]
	add	x0, sp, #40
	CSTR	x1, "<CurrentURI>%s</CurrentURI><CurrentURIMetaData>%s</CurrentURIMetaData>"
	bl	_asprintf
	mov	x0, x21
	bl	_free
	ldr	x20, [sp, #40]
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
	str	w22, [x19, #JOB_RESULT]
	bl	poll_now                  ; show the new track right away
	b	Lret3

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
	CSTR	x2, "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %lld\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
	b	Lpy_print
Lpy_partial:
	ldp	x11, x12, [x19, #PX_POS]
	sub	x13, x12, x11
	add	x13, x13, #1
	stp	x9, x13, [sp]
	stp	x11, x12, [sp, #16]
	str	x10, [sp, #32]
	CSTR	x2, "HTTP/1.1 206 Partial Content\r\nContent-Type: %s\r\nContent-Length: %lld\r\nContent-Range: bytes %lld-%lld/%lld\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
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

; vod_stream(fd, url, range, head) — proxy a media file in chunks the CDN serves at full speed, honoring the speaker's range.
	.equ VS_PX,	16                ; proxy state
	.equ VS_RANGE,	VS_PX + PX_SIZE   ; char[32], upstream range
	.equ VS_A,	VS_RANGE + 32     ; the speaker's first byte
	.equ VS_B,	VS_A + 8          ; and last byte
	.equ VS_SIZE,	VS_B + 8
vod_stream:
	FRAME	4, VS_SIZE
	mov	w20, w0
	mov	x21, x1
	mov	x22, x2
	mov	w24, w3
	bl	_curl_easy_init
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
	ldrb	w9, [x22]
	cbz	w9, Lvs_setup             ; no Range: the whole file from byte 0
	mov	x0, x22
	CSTR	x1, "bytes="
	bl	_strcasestr
	add	x9, x22, #6
	cmp	x0, x22
	csel	x22, x9, x22, eq          ; "bytes=a-b", or a bare "a-b"
	add	x9, sp, #VS_A
	add	x10, sp, #VS_B
	stp	x9, x10, [sp]
	mov	x0, x22
	GADDR	x1, Ls_range
	bl	_sscanf
	cmp	w0, #1
	b.lt	Lvs_setup                 ; unreadable: send it all
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
	bl	_curl_easy_init
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
	bl	vod_stream
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
	mov	x0, #0
	b	Lret4

; server_run(fd) — accept LAN peers, one detached thread per connection.
	ENTRY	server_run
	FRAME	2, 48
	mov	w19, w0
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
	eor	w12, w9, w10
	tst	w12, w11
	b.eq	Lsr_ok                    ; same subnet
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
	b	Lsr_accept
Lsr_drop:
	mov	w0, w20
	bl	_close
	b	Lsr_accept

; server_start() — listen on an OS-assigned port and start the accept thread; w0 = 1 if listening.
server_start:
	FRAME	1, 48
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

; parse_player(job, response) — the best AAC stream, then title, channel, length and live flag; w0 = 1 if there is a stream.
	.pushsection __DATA,__data
Lk_itag:	.asciz	"\"itag\":"
	.popsection
parse_player:
	FRAME	4
	mov	x19, x0
	mov	x20, x1
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
	cbz	x0, Lpp_fmt               ; not AAC: not every speaker plays it
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
	b	Lpp_fmt
Lpp_picked:
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
	mov	w21, #PLAY_FAILED
	bl	_curl_easy_init
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
	strb	wzr, [sp, #RS_VIS]        ; a visitorData first, as the WEB client
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
	str	x22, [sp]
	add	x0, x20, #(JOB_TRACK + T_ART)
	mov	x1, #2048
	CSTR	x2, "https://i.ytimg.com/vi/%s/maxresdefault.jpg"
	bl	_snprintf
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
	.equ VM_DBL,	64                ; d0-d3
	.equ VM_SIZE,	96
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
	stp	d0, d1, [sp, #VM_DBL]
	stp	d2, d3, [sp, #(VM_DBL + 16)]
	mov	x23, #4
	b	Lvm_kind
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
	KIND	Lk_skip
	KIND	Lk_sel                    ; L
	KIND	Lk_skip
	KIND	Lk_skip
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

; text_height(field) -> its height at the content width, rounded up.
text_height:
	FRAME	0
	DBL	d0, Ld_cw
	DBL	d1, Ld_1000
	SEND	S_sizeThatFits_
	frintp	d1, d1
	fcvtzs	w0, d1
	b	Lret0

; layout_text(has_artist) — size title and artist and center the pair in their band under the artwork.
layout_text:
	FRAME	2
	mov	w22, w0
	ldr	x0, [x28, #G_TITLE]
	bl	text_height
	mov	w19, #TITLE_MAX_H
	cmp	w0, w19
	csel	w19, w0, w19, lt          ; two lines at most
	mov	w20, #0                   ; artist height
	mov	w21, #0                   ; gap between them
	cbz	w22, Llx_place
	ldr	x0, [x28, #G_ARTIST]
	bl	text_height
	mov	w20, w0
	mov	w21, #TEXT_GAP
Llx_place:
	add	w9, w19, w20
	add	w9, w9, w21
	mov	w10, #(TEXT_BAND + 2 * TITLE_T)
	sub	w10, w10, w9
	asr	w22, w10, #1              ; the block's top
	mov	x1, #PAD
	bfi	x1, x22, #16, #16
	movk	x1, #CONTENT_W, lsl #32
	bfi	x1, x19, #48, #16
	ldr	x0, [x28, #G_TITLE]
	bl	frame_rect
	SEND	S_setFrame_
	add	w9, w22, w19
	add	w9, w9, w21
	mov	x1, #PAD
	bfi	x1, x9, #16, #16
	movk	x1, #CONTENT_W, lsl #32
	bfi	x1, x20, #48, #16
	ldr	x0, [x28, #G_ARTIST]
	bl	frame_rect
	SEND	S_setFrame_
	b	Lret2

; show_track(title, artist) — render the track text when it changed.
show_track:
	FRAME	2
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
	cbz	w0, Lret2
	ldr	x0, [x28, #G_TITLE]
	ldrb	w9, [x19]
	cbz	w9, Ltr_empty
	mov	x1, x19
	bl	setstr
	CLASS	x0, NSColor
	SEND	S_labelColor
	b	Ltr_color
Ltr_empty:
	GADDR	x1, Ls_nothing
	bl	setstr
	ldr	x0, [x28, #G_SECOND]
Ltr_color:
	mov	x2, x0
	ldr	x0, [x28, #G_TITLE]
	SEND	S_setTextColor_
	ldr	x0, [x28, #G_ARTIST]
	mov	x1, x20
	bl	setstr
	ldrb	w0, [x20]
	bl	layout_text
	b	Lret2

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
	bl	_curl_easy_init
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

; art_show(image, letterboxed) — show an image in the artwork card and the blurred backdrop (nil hides them), cropping 4:3 bars.
art_show:
	FRAME	3
	mov	x19, x0
	mov	w20, w1
	mov	x21, #G_ART
Las_view:
	ldr	x22, [x28, x21]
	mov	x0, x22
	SEND	S_layer
	mov	x23, x0
	fmov	d0, xzr                   ; contentsRect, in unit coordinates
	fmov	d1, xzr
	fmov	d2, #1.0
	fmov	d3, #1.0
	cbz	w20, Las_rect
	fmov	d1, #0.125                ; skip 12.5% at the top and bottom
	fmov	d3, #0.75
Las_rect:
	SEND	S_setContentsRect_
	mov	x0, x23
	mov	x2, x19
	SEND	S_setContents_
	cmp	x19, #0
	cset	w2, eq
	mov	x0, x22
	SEND	S_setHidden_
	cmp	x21, #G_BGART
	mov	x21, #G_BGART
	b.ne	Las_view
	b	Lret3

; art_apply(job) — show the downloaded artwork, or hide it if it is not an image.
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
	SEND	S_release                 ; the layers keep it
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
	ldr	x0, [x28, #G_SECOND]
	cbz	w19, Lrs_color
	CLASS	x0, NSColor
	SEND	S_systemRedColor
Lrs_color:
	mov	x2, x0
	ldr	x0, [x28, #G_STATUS]
	SEND	S_setTextColor_
	b	Lret1

; center_picker() — size the device picker to the selected name and icon, and center it in its row.
center_picker:
	FRAME	1
	ldr	x0, [x28, #G_DEV]
	SEND	S_cell
	fmov	d0, xzr
	fmov	d1, xzr
	DBL	d2, Ld_1000
	DBL	d3, Ld_devh
	SEND	S_titleRectForBounds_
	DBL	d4, Ld_air
	fsub	d4, d4, d2                ; room for the icon, insets and arrows
	frintp	d4, d4
	fcvtzs	w20, d4
	ldr	x0, [x28, #G_DEV]
	SEND	S_titleOfSelectedItem
	mov	x19, x0
	ldr	x0, [x28, #G_DEV]
	SEND	S_font
	mov	x2, x0
	ldr	x9, [x27, #F_NSFontAttributeName]
	ldr	x3, [x9]
	CLASS	x0, NSDictionary
	SEND	S_dictionaryWithObject_forKey_
	mov	x2, x0
	mov	x0, x19
	SEND	S_sizeWithAttributes_ ; d0 = the name's width
	frintp	d0, d0
	scvtf	d4, w20
	fadd	d2, d0, d4
	DBL	d4, Ld_cw
	fmin	d2, d2, d4                ; long names truncate
	DBL	d5, Ld_winw
	fsub	d0, d5, d2
	fmov	d6, #0.5
	fmul	d0, d0, d6                ; x = (WIN_W - width) / 2
	DBL	d1, Ld_devy
	DBL	d3, Ld_devh
	ldr	x0, [x28, #G_DEV]
	SEND	S_setFrame_
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

; rebuild_devices() — the device picker from the device list; items that still match stay, so an open menu only grows.
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
	mov	x23, x0                   ; items shown
	mov	x20, #0
Lrd_same:
	cmp	x20, x23
	ccmp	x20, x19, #2, lo
	b.hs	Lrd_cut
	ldr	x0, [x28, #G_DEV]
	mov	x2, x20
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
	sub	x23, x23, #1
	ldr	x0, [x28, #G_DEV]
	mov	x2, x23
	SEND	S_removeItemAtIndex_
	b	Lrd_cut
Lrd_add:
	cmp	x20, x19
	b.hs	Lret3
	ldr	x0, [x28, #G_DEV]
	SEND	S_menu      ; the menu allows duplicate names
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
	ldr	x0, [x28, #G_DEV]
	mov	x2, x20
	SEND	S_selectItemAtIndex_
	BADDR	x0, B_UIWTITLE           ; window title (for the Window menu and Mission Control)
	add	x1, x19, #NOW_NAME
	mov	x2, #128
	bl	cache_update
	cbz	w0, Lur_track
	BADDR	x0, B_UIWTITLE
	bl	mkstr
	mov	x2, x0
	ldr	x0, [x28, #G_WIN]
	SEND	S_setTitle_
	bl	center_picker
Lur_track:
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
	ldr	x0, [x28, #G_FIELD]
	mov	x2, #0
	SEND	S_selectText_ ; keep the text so it can be fixed
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
	ldr	x0, [x19, #JOB_QUERY]
	bl	_free
	mov	x0, x19
	bl	_free
	bl	Lui_refresh
	b	Lret2

; ---- This Mac: AVPlayer; macOS routes it to the chosen output (speakers, Bluetooth, AirPlay) ----

; local_play(job) — play the resolved media on This Mac.
local_play:
	FRAME	1
	mov	x19, x0
	BADDR	x0, B_LTTRACK
	add	x1, x19, #JOB_TRACK
	mov	x2, #T_SIZE
	bl	_memcpy
	ldr	x9, [x19, #JOB_DUR]
	str	x9, [x28, #G_LTDUR]
	add	x0, x19, #JOB_URL
	add	x9, x19, #JOB_LOCAL
	ldr	w10, [x19, #JOB_LIVE]
	cmp	w10, #0
	csel	x0, x0, x9, eq            ; a live broadcast plays through the proxy
	bl	mkstr
	mov	x2, x0
	CLASS	x0, NSURL
	SEND	S_URLWithString_
	cbz	x0, Lret1
	mov	x2, x0
	CLASS	x0, AVPlayerItem
	SEND	S_playerItemWithURL_
	mov	x20, x0
	ldr	x0, [x28, #G_PLAYER]
	mov	x2, x20
	SEND	S_replaceCurrentItemWithPlayerItem_
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_play
	bl	local_poll
	b	Lret1

; local_poll() — publish This Mac's playback state and re-render.
local_poll:
	FRAME	3, 32                     ; room for a CMTime
	ldr	x0, [x28, #G_PLAYER]
	mov	x19, x0
	SEND	S_currentItem
	mov	w20, #ST_STOPPED
	cbz	x0, Llq_time              ; nothing loaded
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
	mov	x8, sp                    ; a CMTime comes back through x8
	SEND	S_currentTime
	ldr	x9, [sp]                  ; value / timescale (0 / 0 with no item gives 0)
	ldrsw	x10, [sp, #8]
	sdiv	x21, x9, x10
	mov	x0, x19
	SEND	S_volume
	ldr	s1, [x28, #(Lf_100 - G)]
	fmul	s0, s0, s1
	fcvtns	w22, s0
	mov	x0, x19
	SEND	S_isMuted
	mov	w19, w0
	LOCK
	BADDR	x23, B_NOW
	ldr	w9, [x23, #NOW_SEL]
	cbnz	w9, Llq_unlock            ; a device owns the snapshot now
	str	w20, [x23, #NOW_STATE]
	stp	w22, w19, [x23, #NOW_VOL]
	ldr	x9, [x28, #G_LTDUR]
	stp	x21, x9, [x23, #NOW_POS]
	add	x0, x23, #NOW_TITLE
	BADDR	x1, B_LTTRACK
	mov	x2, #T_SIZE
	bl	_memcpy
Llq_unlock:
	UNLOCK
	bl	Lui_refresh
	b	Lret3

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
	FRAME	0, 32
	cmp	x0, #0
	csel	x0, x0, xzr, gt
	mov	x9, #1000                 ; CMTime in milliseconds: value, timescale, flags (valid), epoch
	mul	x0, x0, x9
	movk	x9, #1, lsl #32
	stp	x0, x9, [sp]
	str	xzr, [sp, #16]
	ldr	x0, [x28, #G_PLAYER]
	mov	x2, sp                    ; passed by reference
	SEND	S_seekToTime_
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
	mov	x19, x0
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
	SEND	S_type      ; a nil event gives 0
	cmp	x0, #NSEventTypeLeftMouseDown
	ccmp	x0, #NSEventTypeLeftMouseDragged, #4, ne
	cset	w0, eq
	b	Lret0

; act_play — Return in the search field: resolve and play its link or search.
	ENTRY	act_play
	FRAME	2
	ldr	w9, [x28, #G_LOADING]
	cbnz	w9, Lret2                 ; one link at a time
	ldr	x0, [x28, #G_FIELD]
	SEND	S_stringValue
	mov	x19, x0
	CLASS	x0, NSCharacterSet
	SEND	S_whitespaceAndNewlineCharacterSet
	mov	x2, x0
	mov	x0, x19
	SEND	S_stringByTrimmingCharactersInSet_
	SEND	S_UTF8String
	cbz	x0, Lret2
	ldrb	w9, [x0]
	cbz	w9, Lret2                 ; empty (also the field's clear button)
	mov	x19, x0
	ldr	w9, [x28, #G_READY]
	cbnz	w9, Lap_go
	CSTR	x0, "No device available."
	mov	w1, #1
	bl	set_status
	b	Lret2
Lap_go:
	mov	x0, #1
	mov	x1, #JOB_SIZE
	bl	_calloc
	cbz	x0, Lret2
	mov	x20, x0
	mov	x0, x19
	bl	_strdup                   ; the NSString's buffer dies with the pool
	str	x0, [x20, #JOB_QUERY]
	cbz	x0, Lap_drop
	mov	w9, #1
	str	w9, [x28, #G_LOADING]
	ADDR	x0, Lprog_busy
	bl	ui_run
	GADDR	x0, Ls_slash+1
	mov	w1, #0
	bl	set_status
	WORKQ
	mov	x1, x20
	adr	x2, play_resolve
	bl	_dispatch_async_f
	b	Lret2
Lap_drop:
	mov	x0, x20
	bl	_free
	b	Lret2

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

; act_seek — the position slider; seeks when released.
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
	cbnz	w0, Lret1
	mov	x1, x19
	bl	seek_route
	b	Lret1

; act_tick — the 1 Hz timer: This Mac renders itself; a device is polled, one poll in flight at most.
	ENTRY	act_tick
	ldr	x10, [x28, #G_TICK]
	add	x10, x10, #1
	str	x10, [x28, #G_TICK]
	ldr	w9, [x28, #G_SEL]
	cbz	w9, local_poll
	add	x9, x28, #G_POLLB
	mov	w10, #1
	swpal	w10, w10, [x9]
	cbnz	w10, Lat_ret              ; the previous poll is still running
	ldr	x0, [x28, #G_QUEUE]
	mov	x1, #0
	adr	x2, poll_job
	b	_dispatch_async_f
Lat_ret:
	ret

; act_focus — Cmd-L: bring the window forward and select the search field.
	ENTRY	act_focus
	ADDR	x0, Lprog_focus
	b	ui_run

; act_rescan — Cmd-R: search for devices again (e.g. after changing networks); also the first search.
	ENTRY	act_rescan
	mov	w0, #0
	b	search

; act_scan — the picker opens: look for devices that came up since, keeping the listed ones in place.
	ENTRY	act_scan
	mov	w0, #1
; search(mode) — start a search unless one of its kind is running.
search:
	mov	w9, #1
	lsl	w9, w9, w0
	add	x11, x28, #G_DISC
	ldsetal	w9, w10, [x11]
	tst	w10, w9
	b.ne	Lat_ret                   ; already running
	mov	x1, x0
	WORKQ
	adr	x2, scan_job
	b	_dispatch_async_f

; applicationShouldTerminateAfterLastWindowClosed: -> YES
imp_quit:
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
	ADDR	x0, Lprog_build
	bl	ui_run
	mov	w0, #0                    ; no artist yet
	bl	layout_text
	bl	Lui_refresh
	ADDR	x0, Lprog_show
	bl	ui_run
	bl	server_start
	cbnz	w0, Lmn_discover
	CSTR	x0, "Could not start the audio server."
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
.macro RC x, top, w, h
	.short	\x, \top, \w, \h
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
.macro NEWV class, x, top, w, h
	CLS	\class
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=R"
	RC	\x, \top, \w, \h
	ADDV
.endm
.macro FONT sel, size, weight
	CLS	NSFont
	MSG	\sel, "=DF"
	.short	(\size) * 4
	.byte	\weight
	STO	G_T0
.endm
.macro LABEL slot, text, x, top, w, h, align
	CLS	NSTextField
	MSG	S_labelWithString_, "=S"
	.asciz	"\text"
	STO	\slot
	MSG	S_setFrame_, "R"
	RC	\x, \top, \w, \h
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setTextColor_, "O"
	.byte	G_SECOND >> 3
	MSG	S_setAlignment_, "I"
	.byte	\align
	MSG	S_setLineBreakMode_, "I"
	.byte	4                         ; NSLineBreakByTruncatingTail
	ADDV
.endm
.macro SLIDER slot, action, x, top, w, max
	CLS	NSSlider
	MSG	S_sliderWithTarget_action_, "=OL"
	.byte	G_CTRL >> 3
	.asciz	"\action"
	STO	\slot
	MSG	S_setFrame_, "R"
	RC	\x, \top, \w, SLIDER_H
	MSG	S_setMaxValue_, "D"
	.short	(\max) * 4
	ADDV
.endm
.macro BUTTON slot, sym, desc, action, tip, bx, btop, bsize, pt
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
	MSG	S_setFrame_, "R"
	RC	\bx, \btop, \bsize, \bsize
	MSG	S_setToolTip_, "S"
	.asciz	"\tip"
	ADDV
.endm
.macro ARTVIEW slot, x, top, w, h
	CLS	CALayer
	MSG	S_layer, "="
	MSG	S_setContentsGravity_, "S"
	.asciz	"resizeAspectFill"
	STO	G_T0
	NEWV	NSView, \x, \top, \w, \h
	STO	\slot
	MSG	S_setLayer_, "O"
	.byte	G_T0 >> 3
	MSG	S_setWantsLayer_, "I"
	.byte	1
	MSG	S_setHidden_, "I"
	.byte	1
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

; Services, the controller (every action's target, the app delegate), the menus (Edit enables Cmd-V), the window and its views.
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
	METHOD	"act_focus:", act_focus
	METHOD	"act_rescan:", act_rescan
	METHOD	"act_device:", act_device
	METHOD	"menuWillOpen:", act_scan
	METHOD	"applicationShouldTerminateAfterLastWindowClosed:", imp_quit, "B@:@"
	CALL	F_objc_registerClassPair, "O"
	.byte	G_T0 >> 3
	LD	G_T0
	MSG	S_new, "="
	STO	G_CTRL
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
	SUBMENU	"Edit"
	ITEM	"Undo", "undo:", "z"
	ITEM	"Redo", "redo:", "z"
	MASK	0x120000
	SEP
	ITEM	"Cut", "cut:", "x"
	ITEM	"Copy", "copy:", "c"
	ITEM	"Paste", "paste:", "v"
	ITEM	"Select All", "selectAll:", "a"
	SUBMENU	"Controls"
	ITEM	"Play/Pause", "act_toggle:", " "  ; Space, only when not typing in the field
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
	ITEM	"Paste Link or Search\342\200\246", "act_focus:", "l"
	ITEM	"Find Devices", "act_rescan:", "r"
	SUBMENU	"Window"
	ITEM	"Minimize", "performMiniaturize:", "m"
	ITEM	"Close", "performClose:", "w"
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
	MSG	S_setTitlebarAppearsTransparent_, "I" ; content flows under it
	.byte	1
	MSG	S_setMovableByWindowBackground_, "I"
	.byte	1
	MSG	S_setTitleVisibility_, "I"
	.byte	1                         ; hidden: the title bar holds only the window buttons
	MSG	S_contentView, "="
	STO	G_CONTENT
	MSG	S_setWantsLayer_, "I"     ; within-window blur needs layers
	.byte	1
	CLS	NSAppearance
	MSG	S_appearanceNamed_, "=S"
	.asciz	"NSAppearanceNameDarkAqua"
	STO	G_T0
	LD	G_WIN
	MSG	S_setAppearance_, "O"     ; a dark player, lit by its artwork
	.byte	G_T0 >> 3

	; Backdrop: the artwork, aspect-filled behind everything, under frosted glass.
	ARTVIEW	G_BGART, 0, 0, WIN_W, WIN_H
	NEWV	NSVisualEffectView, 0, 0, WIN_W, WIN_H
	MSG	S_setMaterial_, "I"
	.byte	13                        ; HUD window
	MSG	S_setBlendingMode_, "I"
	.byte	1                         ; within the window
	MSG	S_setState_, "I"
	.byte	1                         ; active

	; Search field: paste a link or type a search, then Return.
	NEWV	NSSearchField, PAD, FIELD_T, CONTENT_W, FIELD_H
	STO	G_FIELD
	MSG	S_setControlSize_, "I"
	.byte	3                         ; large
	MSG	S_setFocusRingType_, "I"
	.byte	1                         ; none: the caret shows focus
	MSG	S_setPlaceholderString_, "S"
	.asciz	"Paste a link or search YouTube"
	MSG	S_setSendsWholeSearchString_, "I" ; act on Return only
	.byte	1
	MSG	S_setTarget_, "O"
	.byte	G_CTRL >> 3
	MSG	S_setAction_, "L"
	.asciz	"act_play:"

	; Artwork placeholder: a rounded fill with a large music note.
	CLS	NSImageSymbolConfiguration
	MSG	S_configurationWithPointSize_weight_, "=DF"
	.short	64 * 4
	.byte	X_REGULAR
	STO	G_T0
	CLS	NSColor
	MSG	S_tertiaryLabelColor, "="
	STO	G_T1
	IMG	G_T2, "music.note", "No artwork"
	CLS	NSImageView
	MSG	S_imageViewWithImage_, "=O"
	.byte	G_T2 >> 3
	MSG	S_setSymbolConfiguration_, "O"
	.byte	G_T0 >> 3
	MSG	S_setContentTintColor_, "O"
	.byte	G_T1 >> 3
	STO	G_T0
	CLS	NSColor
	MSG	S_quaternarySystemFillColor, "="
	STO	G_T1
	NEWV	NSBox, ART_X, ART_T, ART_S, ART_S
	MSG	S_setBoxType_, "I"
	.byte	4                         ; custom
	MSG	S_setTitlePosition_, "I"
	.byte	0                         ; no title
	MSG	S_setBorderWidth_, "D"
	.short	0
	MSG	S_setCornerRadius_, "D"
	.short	ART_RADIUS * 4
	MSG	S_setFillColor_, "O"
	.byte	G_T1 >> 3
	MSG	S_setContentView_, "O"
	.byte	G_T0 >> 3

	; Artwork card over the placeholder, clipped to continuous corners.
	ARTVIEW	G_ART, ART_X, ART_T, ART_S, ART_S
	MSG	S_setClipsToBounds_, "I"  ; AppKit mirrors it into masksToBounds
	.byte	1
	MSG	S_layer, "="
	MSG	S_setCornerRadius_, "D"
	.short	ART_RADIUS * 4
	MSG	S_setCornerCurve_, "S"
	.asciz	"continuous"

	; Spinner over the artwork while a link resolves.
	NEWV	NSProgressIndicator, ART_X + (ART_S - SPIN_S) / 2, ART_T + (ART_S - SPIN_S) / 2, SPIN_S, SPIN_S
	STO	G_SPIN
	MSG	S_setStyle_, "I"
	.byte	1                         ; spinning
	MSG	S_setDisplayedWhenStopped_, "I"
	.byte	0

	; Title (two lines, truncated) and artist, centered under the artwork by layout_text.
	CLS	NSColor
	MSG	S_secondaryLabelColor, "="
	MSG	S_retain, "="
	STO	G_SECOND
	FONT	S_systemFontOfSize_weight_, 17, X_SEMIBOLD
	CLS	NSTextField
	MSG	S_wrappingLabelWithString_, "=S"
	.asciz	"Nothing playing"
	STO	G_TITLE
	MSG	S_setSelectable_, "I"
	.byte	0
	MSG	S_setMaximumNumberOfLines_, "I"
	.byte	2
	MSG	S_setAlignment_, "I"
	.byte	1                         ; centered
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setTextColor_, "O"
	.byte	G_SECOND >> 3
	ADDV
	MSG	S_cell, "="
	MSG	S_setTruncatesLastVisibleLine_, "I"
	.byte	1
	FONT	S_systemFontOfSize_weight_, 13, X_REGULAR
	LABEL	G_ARTIST, "", PAD, TITLE_T, CONTENT_W, ARTIST_H, 1

	; Progress: slider, then elapsed and remaining time (fixed-width digits).
	SLIDER	G_POS, "act_seek:", PAD, SEEK_T, CONTENT_W, 1
	FONT	S_monospacedDigitSystemFontOfSize_weight_, 11, X_MEDIUM
	LABEL	G_CUR, "0:00", PAD, TIME_T, TIME_W, LABEL_H, 0
	LABEL	G_DUR, "--:--", WIN_W - PAD - TIME_W, TIME_T, TIME_W, LABEL_H, 2

	; Transport: -10 s, play/pause, +10 s (Stop lives in the Controls menu).
	BUTTON	G_BACK, "gobackward.10", "Back 10 seconds", "act_back:", "Back 10 seconds (\342\214\230\342\206\220)", BACK_X, SMALL_T, BTN_S, 22
	BUTTON	G_PP, "play.fill", "Play or pause", "act_toggle:", "Play or pause (Space)", PLAY_X, PLAY_T, PLAY_S, 34
	BUTTON	G_FWD, "goforward.10", "Forward 10 seconds", "act_fwd:", "Forward 10 seconds (\342\214\230\342\206\222)", FWD_X, SMALL_T, BTN_S, 22

	; Volume: mute toggle, slider, loud icon.
	BUTTON	G_MUTE, "speaker.wave.2.fill", "Mute", "act_mute:", "Mute (\342\214\245\342\214\230\342\206\223)", PAD, VOL_T - 1, VOL_ICON_S, 13
	SLIDER	G_VOL, "act_vol:", VOL_X, VOL_T, VOL_W, 100
	IMG	G_T2, "speaker.wave.3.fill", "Maximum volume"
	CLS	NSImageView
	MSG	S_imageViewWithImage_, "=O"
	.byte	G_T2 >> 3
	MSG	S_setContentTintColor_, "O"
	.byte	G_SECOND >> 3
	MSG	S_setFrame_, "R"
	RC	VMAX_X, VOL_T, VOL_ICON_S, SLIDER_H
	ADDV

	; Playing on: the device picker, centered in its own row by center_picker.
	FONT	S_systemFontOfSize_weight_, 12, X_MEDIUM
	CLS	NSPopUpButton
	MSG	S_new, "="
	STO	G_DEV
	MSG	S_setBordered_, "I"
	.byte	0
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setTarget_, "O"
	.byte	G_CTRL >> 3
	MSG	S_setAction_, "L"
	.asciz	"act_device:"
	MSG	S_setToolTip_, "S"
	.asciz	"Play on"
	ADDV
	MSG	S_menu, "="               ; its opening starts a search
	MSG	S_setDelegate_, "O"
	.byte	G_CTRL >> 3

	; Status line: errors in red, hints in grey.
	FONT	S_systemFontOfSize_weight_, 11, X_REGULAR
	LABEL	G_STATUS, "", PAD, STATUS_T, CONTENT_W, LABEL_H, 1

	; Images swapped by ui_refresh.
	IMAGE	G_IMGPLAY, "play.fill", "Play"
	IMAGE	G_IMGPAUSE, "pause.fill", "Pause"
	IMAGE	G_IMGMUTED, "speaker.slash.fill", "Unmute"
	IMAGE	G_IMGUNMUTED, "speaker.wave.2.fill", "Mute"
	OP_END

; Centered; the position is not saved, so the app writes no preferences.
Lprog_show:
	LD	G_WIN
	MSG	S_center
	MSG	S_makeKeyAndOrderFront_, "I"
	.byte	0
	MSG	S_makeFirstResponder_, "O" ; ready to paste right away
	.byte	G_FIELD >> 3
	OP_END

; While a link resolves: the spinner turns and the field waits; then they rest.
Lprog_busy:
	LD	G_FIELD
	MSG	S_setEnabled_, "I"
	.byte	0
	LD	G_SPIN
	MSG	S_startAnimation_, "I"
	.byte	0
	OP_END
Lprog_idle:
	LD	G_SPIN
	MSG	S_stopAnimation_, "I"
	.byte	0
	LD	G_FIELD
	MSG	S_setEnabled_, "I"
	.byte	1
	OP_END

; Played: the field empties and gives up focus, so Space plays and pauses again.
Lprog_played:
	LD	G_FIELD
	MSG	S_setStringValue_, "S"
	.asciz	""
	LD	G_WIN
	MSG	S_makeFirstResponder_, "I"
	.byte	0
	OP_END

; Cmd-L: the window forward, the search field selected.
Lprog_focus:
	LD	G_WIN
	MSG	S_makeKeyAndOrderFront_, "I"
	.byte	0
	LD	G_FIELD
	MSG	S_selectText_, "I"
	.byte	0
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
