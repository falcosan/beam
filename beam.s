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

; TYPE reg, a, b, c, d — a four-character code as it reads from memory, e.g. a box type.
.macro TYPE reg, a, b, c, d
	mov	\reg, #((\a) | (\b) << 8)
	movk	\reg, #((\c) | (\d) << 8), lsl #16
.endm

; CSTR reg, text — a C string literal, kept after G.
.macro CSTR reg, text
	.pushsection __TEXT,__cstring,cstring_literals
Lc\@:	.asciz	"\text"
	.popsection
	adrp	\reg, Lc\@@PAGE
	add	\reg, \reg, Lc\@@PAGEOFF
.endm

; LOCK / UNLOCK — the lock guarding the playlist slots and visitorData.
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

; BSD sockets, signals and GCD.
.equ AF_INET,                    2
.equ SOCK_STREAM,                1
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
.equ ART_TIMEOUT_MS,             10000
.equ API_TIMEOUT_MS,             30000
.equ BUF_MAX,                    0x800000 ; 8 MiB cap for any buffered body
.equ REQ_MAX,                    4096
.equ CHUNK,                      0xa00000 ; 10 MiB: larger upstream ranges are throttled to realtime
.equ CLIENT_TIMEOUT_S,           10
.equ ACCEPT_BACKOFF_US,          10000
.equ SLOTS,                      32       ; a video on This Mac takes five: picture, sound and their playlists
.equ TOKEN_STRIDE,               40       ; 32 hex + NUL; the last byte flags a live stream
.equ HIDE_TICKS,                 3        ; idle seconds before the controls leave a playing video
.equ VIDEO_MAX_H,                2160     ; the tallest video stream picked
.equ SKIP_SECONDS,               10
.equ VOLUME_STEP,                5

; The engine: This Mac's own player.
.equ QOS_CLASS_USER_INTERACTIVE, 0x21
.equ PROT_READ,                  1
.equ MAP_PRIVATE,                2
.equ MADV_SEQUENTIAL,            2
.equ STAT_SIZE,                  96       ; struct stat: st_size
.equ RENDER_FAILED,              2        ; AVQueuedSampleBufferRenderingStatusFailed
.equ WAIT_TRIES,                 2000     ; 5 ms polls for the first picture before the clock starts anyway
.equ WAIT_NS,                    5000000
.equ AUDIO_PREROLL,              2        ; packets decoded before a seek target, so the decoder has its overlap
.equ TRACKS,                     8
.equ RQS,                        16       ; requests at once
.equ STREAMS,                    3        ; network streams: picture, sound, subtitles
.equ FIFO_N,                     2048     ; samples a track's queue holds
.equ AHEAD_V,                    480      ; queued pictures and sound packets before a stream stops fetching
.equ AHEAD_A,                    768
.equ AHEAD_S,                    64       ; and cues
.equ ARENA_MAX,                  0x800000 ; 8 MiB of media data per arena
.equ BOX_MAX,                    0x1000000 ; the largest box collected (moov, moof, sidx)
.equ RETRY_NS,                   1000000000
.equ NET_TRIES,                  3
.equ TICK_NS,                    250000000 ; the network check: a stall holds the clock until STALL_FULL ms are in
.equ STALL_LOW,                  250
.equ STALL_FULL,                 2000
.equ BPS_START,                  4000000  ; HLS starts with the best variant under this, then follows the measured speed
.equ HLS_LIVE_BACK,              3        ; a broadcast starts this many segments from its live edge
.equ CLOCK_UPTIME_RAW,           8
.equ AFS_READY,                  0x72656479 ; 'redy'
.equ AFS_FORMAT,                 0x64666d74 ; 'dfmt'
.equ AFS_COOKIE,                 0x6d676963 ; 'mgic'
.equ AFS_DOFF,                   0x646f6666 ; 'doff': where the sound data starts
.equ AFS_PCNT,                   0x70636e74 ; 'pcnt': its packets
.equ AFS_BRAT,                   0x62726174 ; 'brat': its bit rate
; seg_scan's result: a media playlist's segment.
.equ SG_URI,                     0        ; its URI line, and the line's end
.equ SG_URIE,                    8
.equ SG_T,                       16       ; start and duration, ms
.equ SG_DUR,                     24
.equ SG_BRL,                     32       ; byte range: length (0: all) and offset
.equ SG_BRO,                     40
.equ SG_KEY,                     48       ; its EXT-X-KEY line, or 0
.equ SG_MAP,                     56       ; its EXT-X-MAP line, or 0
.equ SG_SEQ,                     64       ; its media sequence number
.equ SG_SEQ0,                    72       ; the playlist's first
.equ SG_TDUR,                    80       ; w: target duration, ms
.equ SG_END,                     84       ; w: EXT-X-ENDLIST
.equ SG_DISC,                    88       ; w: a discontinuity before it
.equ SG_N,                       92       ; w: segments counted
.equ SG_SIZE,                    96

; Request record: what becomes of a task's bytes and of its end.
.equ RQ_SINK,                    0        ; sink(record, bytes, length)
.equ RQ_DONE,                    8        ; done(record, ok, task)
.equ RQ_REQ,                     16       ; the NSURLRequest to start
.equ RQ_TASK,                    24       ; its task, while it runs
.equ RQ_BUF,                     32       ; {data, len}: fetch's body
.equ RQ_SEM,                     48       ; signaled when fetch's request ends
.equ RQ_OK,                      56       ; w
.equ RQ_SIZE,                    64

; A YouTube play for the engine: generation, live, length in ms, picture and sound URLs (owned).
.equ YT_GEN,                     0
.equ YT_LIVE,                    4
.equ YT_DUR,                     8
.equ YT_V,                       16
.equ YT_A,                       24

; Track: one stream of an open file, its sample tables read in place, and a cursor over them.
.equ TR_KIND,                    0        ; w: 'v' picture, 'a' sound, 0 none
.equ TR_TS,                      4        ; w: timescale
.equ TR_FD,                      8        ; CMFormatDescription
.equ TR_SHIFT,                   16       ; the edit list's start, in timescale units
.equ TR_TGT,                     24       ; earlier samples are decoded, not shown or heard
.equ TR_N,                       32       ; w: samples
.equ TR_FIXED,                   36       ; w: every sample's size, or 0
.equ TR_STSD,                    40       ; the first sample description
.equ TR_STTS,                    48       ; table payloads (version and flags first), 0 if absent
.equ TR_CTTS,                    56
.equ TR_STSC,                    64
.equ TR_STSZ,                    72
.equ TR_STCO,                    80
.equ TR_CO64,                    88
.equ TR_STSS,                    96
.equ TR_NST,                     104      ; w: their entries
.equ TR_NCT,                     108
.equ TR_NSC,                     112
.equ TR_NCH,                     116
.equ TR_NSS,                     120
.equ TR_STSDN,                   124      ; w: the description's length
.equ TR_I,                       128      ; the cursor (64 bytes): w sample
.equ TR_STI,                     132      ; w: stts entry, and samples left in it
.equ TR_STL,                     136
.equ TR_CTI,                     140      ; w: ctts entry, and samples left in it
.equ TR_CTL,                     144
.equ TR_SCI,                     148      ; w: stsc entry
.equ TR_CH,                      152      ; w: chunk, and samples left in it
.equ TR_CHL,                     156
.equ TR_SSI,                     160      ; w: the first stss entry at or past the sample
.equ TR_DTS,                     168
.equ TR_OFF,                     176      ; the sample's file offset
.equ TR_FH,                      192      ; w: its queue's head and tail
.equ TR_FT,                      196
.equ TR_FN,                      200      ; w: fragment samples listed, and the next one
.equ TR_FI,                      204
.equ TR_DDUR,                    208      ; w: trex defaults: duration, size, flags
.equ TR_DSIZE,                   212
.equ TR_DFLAGS,                  216
.equ TR_FCAP,                    220      ; w: the list's room
.equ TR_SRC,                     224      ; w: 0 the mapped file, 1 a stream's queue
.equ TR_ID,                      228      ; w: track_ID
.equ TR_STARVE,                  232      ; w: the renderer stopped asking on an empty queue
.equ TR_LANG,                    236      ; w: its language's three letters ("eng"), 0 if none
.equ TR_FQ,                      240      ; the queue: CMSampleBufferRef[FIFO_N]
.equ TR_FL,                      248      ; the fragment's samples: {offset, size, duration, composition, flags}[]
.equ TR_ST,                      256      ; the stream that feeds it
.equ TR_FDTS,                    264      ; the next fragment sample's decode time
.equ TR_LAST,                    272      ; the last sample made's presentation time
.equ TR_AFS,                     280      ; its AudioFileStream, which finds the packets of a sound stream
.equ TR_APTS,                    288      ; the next packet's presentation time
.equ TR_ASR,                     296      ; w: sample rate and frames per packet
.equ TR_AFPP,                    300
.equ TR_ROT,                     304      ; w: the picture's turn from its matrix, degrees counterclockwise (0, 90, 180, -90)
.equ TR_DW,                      308      ; w: its shown size, pixel aspect and clean aperture applied
.equ TR_DH,                      312
.equ TR_AFLAG,                   316      ; w: a sound file's next parse: 1 after a seek (a discontinuity)
.equ TR_SNAP,                    320      ; a saved cursor
.equ TR_SIZE,                    512

; Stream: one URL's bytes from the network, parsed as they come.
.equ ST_URL,                     0        ; char*, owned
.equ ST_LEN,                     8        ; its size, 0 if unknown
.equ ST_POS,                     16       ; the next byte to ask for
.equ ST_SPOS,                    24       ; the next byte to parse
.equ ST_LEFT,                    32       ; bytes left in the box or media data
.equ ST_BOXPOS,                  40       ; where the box started
.equ ST_BBUF,                    48       ; a small box being collected, and its bytes so far
.equ ST_BN,                      56
.equ ST_MOOV,                    64       ; the movie box, kept: a whole file's cursors read its tables
.equ ST_SIDX,                    72       ; the segment index, kept for seeks, and where it ended
.equ ST_SIDXEND,                 80
.equ ST_AR,                      88       ; the arena: media data as it arrives
.equ ST_ARBB,                    96       ; its CMBlockBuffer, which frees it after the last sample
.equ ST_ARPOS,                   104      ; the stream position of its first byte
.equ ST_ARN,                     112
.equ ST_ARCAP,                   120
.equ ST_MDEND,                   128      ; where the media data ends
.equ ST_TR,                      136      ; the tracks it feeds (2)
.equ ST_SQ,                      152      ; a live stream's next segment
.equ ST_PEND,                    160      ; a seek waiting for the index, ms, or -1
.equ ST_GOT,                     168      ; bytes the running request gave
.equ ST_PST,                     176      ; w: 0 box header, 1 box to collect, 2 media data, 3 to skip
.equ ST_HN,                      180      ; w: header bytes so far
.equ ST_HB,                      184      ; the header (16 bytes)
.equ ST_BOXT,                    200      ; w: the box's type
.equ ST_FETCH,                   204      ; w: a request runs
.equ ST_EOS,                     208      ; w: no more bytes
.equ ST_ERRS,                    212      ; w: failures in a row
.equ ST_LIVE,                    216      ; w: live, by segment number
.equ ST_FRAG,                    220      ; w: fragmented: samples come from moof boxes
.equ ST_RETRY,                   224      ; w: a retry is scheduled
.equ ST_ANS,                     228      ; w: the running request's answer was checked
.equ ST_SKIP,                    232      ; bytes of it still to drop: a server without ranges sends from byte 0
.equ ST_RQ,                      240      ; its request record
.equ ST_KIND,                    304      ; w: 0 one URL's bytes, 1 an HLS media playlist's segments
.equ ST_REQT,                    308      ; w: what the request fetches: 0 stream bytes, 1 a playlist, 2 a key, 3 a segment, 4 an init segment
.equ ST_TXT,                     312      ; text being collected (a playlist, a key, an encrypted segment), and its length
.equ ST_TXTN,                    320
.equ ST_PLURL,                   328      ; char*: the media playlist's URL
.equ ST_PL,                      336      ; char*: its text
.equ ST_SEQ,                     344      ; the next segment's media sequence number
.equ ST_SEGT,                    352      ; its start, ms
.equ ST_KEYURL,                  360      ; char*: the key in ST_KEY
.equ ST_MAPURL,                  368      ; char*: the init segment read
.equ ST_T1,                      376      ; when the segment's request started, ns
.equ ST_SEGF,                    384      ; w: the segment's format: 0 unknown, 1 TS, 2 boxes, 3 packed audio
.equ ST_ENC,                     388      ; w: it is AES-128 encrypted
.equ ST_TDUR,                    392      ; w: target duration, ms
.equ ST_ENDED,                   396      ; w: the playlist is complete (on demand)
.equ ST_PMT,                     400      ; w: TS: the program map's PID, the picture's, the sound's
.equ ST_VPID,                    404
.equ ST_APID,                    408
.equ ST_VHEVC,                   412      ; w: the picture is HEVC
.equ ST_TSN,                     416      ; w: bytes of a partial TS packet
.equ ST_PSNEW,                   420      ; w: parameter sets changed: a new format before the next picture
.equ ST_STALE,                   424      ; w: the live playlist is due again
.equ ST_KEY,                     432      ; AES key and IV, 16 bytes each
.equ ST_IV,                      448
.equ ST_VT,                      464      ; the TS picture and sound tracks
.equ ST_AT,                      472
.equ ST_VPES,                    480      ; the PES being gathered, picture and sound: {data, len, cap}
.equ ST_APES,                    504
.equ ST_TSC,                     528      ; a partial TS packet (188)
.equ ST_PS,                      720      ; parameter sets: VPS, SPS, PPS, each {w length, bytes[252]}
.equ ST_RQURL,                   ST_PS + 3 * 256 ; char*: the URL a request of the stream's own runs for
.equ ST_VPEN,                    ST_RQURL + 8 ; the picture's access unit waiting for the next PES, which may end it: {data, len, room, pts, dts, the last duration}
.equ ST_SIZE,                    ST_VPEN + 48

; Track: title, artist and artwork URL.
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

; Play job: main -> worker -> main.
.equ JOB_QUERY,                  0        ; char*, a link, search text or file path (owned)
.equ JOB_RESULT,                 8        ; int, PLAY_*
.equ JOB_LIVE,                   12       ; int
.equ JOB_DUR,                    16       ; seconds, 0 when live or unknown
.equ JOB_ERR,                    24       ; char*, why it failed, or NULL
.equ JOB_KIND,                   32       ; int, KIND_*
.equ JOB_GEN,                    36       ; int, G_PLAYGEN when asked
.equ JOB_ITEM,                   40       ; AVPlayerItem for This Mac, retained, or nil
.equ JOB_TRACK,                  48       ; Track
.equ JOB_AFMT,                   JOB_TRACK + T_SIZE ; Fmt of the sound stream
.equ JOB_VFMT,                   JOB_AFMT + FMT_SIZE ; and of the picture stream
.equ JOB_MSG,                    JOB_VFMT + FMT_SIZE ; char[128], an error message
.equ JOB_URL,                    JOB_MSG + 128      ; char[4096], the media URL
.equ JOB_VURL,                   JOB_URL + 4096     ; char[4096], the video stream's URL, or ""
.equ JOB_TVFMT,                  JOB_VURL + 4096    ; Fmt of the picture for a TV (H.264, up to 1080p)
.equ JOB_TVURL,                  JOB_TVFMT + FMT_SIZE ; char[4096], its URL, or ""
.equ JOB_SIZE,                   JOB_TVURL + 4096
.equ KIND_YOUTUBE,               0        ; a YouTube link or search
.equ KIND_WEB,                   1        ; any other web address, played as it is
.equ KIND_FILE,                  2        ; a file on this Mac (JOB_QUERY is its path)
.equ PLAY_OK,                    0
.equ PLAY_FAILED,                1

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
.equ STAGE_B,                    BAR_M + BAR_H + 16 ; artwork and link field sit between the bar
.equ STAGE_T,                    40       ; and the title bar
.equ ART_RADIUS,                 14
.equ ART_MAX,                    720
.equ SPIN_S,                     32
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
.equ AIR_W,                      28
.equ AIR_X,                      BAR_W - 16 - AIR_W
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
.equ G_PLAYER,                   32       ; AVPlayer
.equ G_LAN,                      40       ; mask << 32 | address, network order, one atomic word
.equ G_LOCK,                     48       ; os_unfair_lock
.equ G_PORT,                     52       ; proxy port
.equ G_SLOTI,                    80       ; next stream slot (lock)
.equ G_PLAYGEN,                  84       ; the newest play (written on main)
.equ G_LTDUR,                    96       ; This Mac's duration (main)
.equ G_TICK,                     104      ; timer ticks since launch
.equ G_SEEKH,                    112      ; tick until which polled positions are ignored
.equ G_VOLH,                     120      ; tick until which polled volumes are ignored
.equ G_MSGT,                     128      ; tick after which the status message expires
.equ G_ARTGEN,                   136      ; artwork request generation
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
.equ G_PP,                       280
.equ G_MUTE,                     288
.equ G_VOL,                      296
.equ G_VIDEO,                    304      ; the view of This Mac's picture
.equ G_STATUS,                   312
.equ G_IMGPLAY,                  328
.equ G_IMGPAUSE,                 336
.equ G_IMGMUTED,                 344
.equ G_IMGUNMUTED,               352
.equ G_SLOTURL,                  360      ; char*[SLOTS], media URLs or playlists (lock)
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
.equ G_URLBOX,                   G_BAR + 8 ; Open from URL's floating field
.equ G_AOBTN,                    G_URLBOX + 8 ; the Audio Only button and menu item
.equ G_AOITEM,                   G_AOBTN + 8
.equ G_ARTASP,                   G_AOITEM + 8 ; the artwork's height / width (double)
.equ G_IDLE,                     G_ARTASP + 8 ; ticks since the mouse last moved
.equ G_HASVIDEO,                 G_IDLE + 4 ; This Mac's media has a picture
.equ G_BARHID,                   G_HASVIDEO + 4 ; the bar is faded out
.equ G_HOVER,                    G_BARHID + 4 ; the mouse is over the bar
.equ G_ARTOK,                    G_HOVER + 4 ; the artwork has an image
.equ G_FAILED,                   G_ARTOK + 4 ; This Mac's item failed and it was reported
.equ G_AV1,                      G_FAILED + 4 ; AV1 decodes in hardware
.equ G_NOTE,                     G_AV1 + 8 ; the artwork card's music note, shown without an image
.equ G_RATE,                     G_NOTE + 8 ; Playback > Speed (float)
.equ G_SUBMENU,                  G_RATE + 8 ; View > Subtitles
.equ G_PIP,                      G_SUBMENU + 8 ; the Picture in Picture controller, made on first use
.equ G_MEDIAQ,                   G_PIP + 8 ; the engine's serial queue
.equ G_SBV,                      G_MEDIAQ + 8 ; the view of the engine's picture
.equ G_SBLAYER,                  G_SBV + 8 ; and its layer, made on the media queue
.equ G_MODE,                     G_SBLAYER + 8 ; 0: the engine plays, 1: AVPlayer (main)
.equ G_PLAYING,                  G_MODE + 4 ; the engine should be playing (main)
.equ G_VOLPCT,                   G_PLAYING + 4 ; volume 0..100 and mute, for both players (main)
.equ G_MUTED,                    G_VOLPCT + 4
.equ G_SEEKPEND,                 G_MUTED + 4 ; a seek is queued for the engine
.equ G_SEEKTO,                   G_SEEKPEND + 8 ; its target, ms
.equ G_SIZE,                     G_SEEKTO + 8

; ---- Data ----

	.section __DATA,__data
	.p2align 3
G:	.space	G_SIZE
Lf_100:	.float	100.0                     ; volume percent, 8-aligned after G
	.float	0.0

; B: the large buffers, at fixed offsets from x27.
.equ B_SLOTTOK,                  0        ; stream tokens (lock)
.equ B_UIMSG,                    B_SLOTTOK + SLOTS * TOKEN_STRIDE ; char[256], status message (main)
.equ B_UIARTIST,                 B_UIMSG + 256 ; char[256], last rendered artist (main)
.equ B_UIART,                    B_UIARTIST + 256 ; char[2048], artwork shown or loading (main)
.equ B_UITITLE,                  B_UIART + 2048 ; char[512], last rendered title (main)
.equ B_LTTRACK,                  B_UITITLE + 512 ; This Mac's track (main)
.equ B_REG,                      (B_LTTRACK + T_SIZE + 4095) & ~4095 ; the registry, 4 KiB-aligned: one add reaches it


; SYM / OBJC name — an imported symbol / class in the registry (FN, defined with each pass, is a function called by name).
.macro SYM name
	REG	F_\name, "\name"
.endm
.macro OBJC name                          ; found with objc_getClass
	REG	C_\name, "\name"
.endm

; REGISTRY — imported symbols, classes, then selectors, looked up by name once at launch into B.
.macro REGISTRY
	FN	CFArrayGetValueAtIndex
	FN	CFDictionarySetValue
	FN	CFRelease
	FN	CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData
	FN	CMBlockBufferCreateWithBufferReference
	FN	CMBlockBufferCreateWithMemoryBlock
	FN	CMSampleBufferCreateReady
	FN	CMSampleBufferGetSampleAttachmentsArray
	FN	CMSetAttachment
	FN	CMTimeCopyAsDictionary
	FN	CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData
	FN	CMVideoFormatDescriptionCreateFromH264ParameterSets
	FN	CMVideoFormatDescriptionCreateFromHEVCParameterSets
	FN	CMAudioFormatDescriptionCreate
	FN	CMAudioSampleBufferCreateReadyWithPacketDescriptions
	FN	CMBlockBufferGetDataPointer
	FN	CMFormatDescriptionCreate
	FN	CMFormatDescriptionGetMediaSubType
	FN	CMSampleBufferGetDataBuffer
	FN	CMSampleBufferGetDuration
	FN	CMSampleBufferGetFormatDescription
	FN	CMSampleBufferGetPresentationTimeStamp
	FN	CMVideoFormatDescriptionGetPresentationDimensions
	FN	AudioFileStreamClose
	FN	AudioFileStreamGetProperty
	FN	AudioFileStreamGetPropertyInfo
	FN	AudioFileStreamOpen
	FN	AudioFileStreamParseBytes
	FN	AudioFileStreamSeek
	FN	VTDecompressionSessionCreate
	FN	VTDecompressionSessionInvalidate
	FN	CCCrypt
	FN	accept
	FN	arc4random_buf
	FN	arc4random_uniform
	FN	asprintf
	FN	bind
	FN	bzero
	FN	calloc
	FN	clock_gettime_nsec_np
	FN	close
	FN	dispatch_after_f
	FN	dispatch_async_f
	FN	dispatch_semaphore_create
	FN	dispatch_semaphore_signal
	FN	dispatch_semaphore_wait
	FN	dispatch_sync_f
	FN	dispatch_time
	FN	free
	FN	freeifaddrs
	FN	fstat
	FN	getifaddrs
	FN	getsockname
	FN	listen
	FN	madvise
	FN	malloc
	FN	memcmp
	FN	memcpy
	FN	memmove
	FN	mmap
	FN	munmap
	FN	objc_autoreleasePoolPop
	FN	objc_autoreleasePoolPush
	FN	objc_getClass
	FN	objc_msgSend
	FN	open
	FN	os_unfair_lock_lock
	FN	os_unfair_lock_unlock
	FN	pthread_create
	FN	pthread_detach
	FN	realloc
	FN	recv
	FN	sel_registerName
	FN	setsockopt
	FN	snprintf
	FN	socket
	FN	strcasestr
	FN	strchr
	FN	strcmp
	FN	strcspn
	FN	strdup
	FN	strlcpy
	FN	strlen
	FN	strncmp
	FN	strnstr
	FN	strstr
	FN	strtod
	FN	strtol
	FN	usleep
	FN	write
	SYM	NSFontWeightMedium
	SYM	NSFontWeightRegular
	SYM	NSFontWeightSemibold
	SYM	VTIsHardwareDecodeSupported
	SYM	_NSConcreteGlobalBlock
	SYM	_dispatch_main_q
	SYM	class_addMethod
	SYM	dispatch_get_global_queue
	SYM	dispatch_queue_attr_make_with_autorelease_frequency
	SYM	dispatch_queue_attr_make_with_qos_class
	SYM	dispatch_queue_create
	SYM	kCFBooleanTrue
	SYM	kCMImageDescriptionFlavor_ISOFamily
	SYM	kCMSampleAttachmentKey_DoNotDisplay
	SYM	kCMSampleAttachmentKey_NotSync
	SYM	kCMSampleBufferAttachmentKey_TrimDurationAtStart
	SYM	kCMSoundDescriptionFlavor_ISOFamily
	SYM	objc_allocateClassPair
	SYM	objc_registerClassPair
	SYM	signal
	REGCLS
	OBJC	AVPlayer
	OBJC	AVPlayerItem
	OBJC	AVPictureInPictureController
	OBJC	AVPictureInPictureControllerContentSource
	OBJC	AVPlayerLayer
	OBJC	AVRoutePickerView
	OBJC	AVSampleBufferAudioRenderer
	OBJC	AVSampleBufferDisplayLayer
	OBJC	AVSampleBufferRenderSynchronizer
	OBJC	CALayer
	OBJC	CATextLayer
	OBJC	CATransaction
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
	OBJC	NSLocale
	OBJC	NSMenu
	OBJC	NSMenuItem
	OBJC	NSMutableURLRequest
	OBJC	NSObject
	OBJC	NSOpenPanel
	OBJC	NSOperationQueue
	OBJC	NSProgressIndicator
	OBJC	NSSlider
	OBJC	NSString
	OBJC	NSTextField
	OBJC	NSTimer
	OBJC	NSTrackingArea
	OBJC	NSURL
	OBJC	NSURLSession
	OBJC	NSURLSessionConfiguration
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
	REG	S_cancelOperation_, "cancelOperation:"
	REG	S_cell, "cell"
	REG	S_center, "center"
	REG	S_clickCount, "clickCount"
	REG	S_colorWithSRGBRed_green_blue_alpha_, "colorWithSRGBRed:green:blue:alpha:"
	REG	S_componentsSeparatedByString_, "componentsSeparatedByString:"
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
	REG	S_imageWithSystemSymbolName_accessibilityDescription_, "imageWithSystemSymbolName:accessibilityDescription:"
	REG	S_initWithContentRect_styleMask_backing_defer_, "initWithContentRect:styleMask:backing:defer:"
	REG	S_initWithData_, "initWithData:"
	REG	S_initWithFrame_, "initWithFrame:"
	REG	S_initWithRect_options_owner_userInfo_, "initWithRect:options:owner:userInfo:"
	REG	S_initWithTitle_, "initWithTitle:"
	REG	S_intValue, "intValue"
	REG	S_isEnabled, "isEnabled"
	REG	S_isEqualToString_, "isEqualToString:"
	REG	S_isExternalPlaybackActive, "isExternalPlaybackActive"
	REG	S_isFileURL, "isFileURL"
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
	REG	S_objectAtIndex_, "objectAtIndex:"
	REG	S_setContentView_, "setContentView:"
	REG	S_size, "size"
	REG	S_sliderWithTarget_action_, "sliderWithTarget:action:"
	REG	S_addRenderer_, "addRenderer:"
	REG	S_enqueueSampleBuffer_, "enqueueSampleBuffer:"
	REG	S_flush, "flush"
	REG	S_flushWithRemovalOfDisplayedImage_completionHandler_, "flushWithRemovalOfDisplayedImage:completionHandler:"
	REG	S_isReadyForDisplay, "isReadyForDisplay"
	REG	S_isReadyForMoreMediaData, "isReadyForMoreMediaData"
	REG	S_requestMediaDataWhenReadyOnQueue_usingBlock_, "requestMediaDataWhenReadyOnQueue:usingBlock:"
	REG	S_sampleBufferRenderer, "sampleBufferRenderer"
	REG	S_setAudioTimePitchAlgorithm_, "setAudioTimePitchAlgorithm:"
	REG	S_setRate_time_, "setRate:time:"
	REG	S_stopRequestingMediaData, "stopRequestingMediaData"
	REG	S_bytes, "bytes"
	REG	S_cancel, "cancel"
	REG	S_dataTaskWithRequest_, "dataTaskWithRequest:"
	REG	S_defaultSessionConfiguration, "defaultSessionConfiguration"
	REG	S_length, "length"
	REG	S_requestWithURL_, "requestWithURL:"
	REG	S_response, "response"
	REG	S_resume, "resume"
	REG	S_sessionWithConfiguration_delegate_delegateQueue_, "sessionWithConfiguration:delegate:delegateQueue:"
	REG	S_setAssumesHTTP3Capable_, "setAssumesHTTP3Capable:"
	REG	S_setHTTPBody_, "setHTTPBody:"
	REG	S_setHTTPMethod_, "setHTTPMethod:"
	REG	S_setTimeoutInterval_, "setTimeoutInterval:"
	REG	S_setUnderlyingQueue_, "setUnderlyingQueue:"
	REG	S_setValue_forHTTPHeaderField_, "setValue:forHTTPHeaderField:"
	REG	S_statusCode, "statusCode"
	REG	S_valueForHTTPHeaderField_, "valueForHTTPHeaderField:"
	REG	S_URLWithString_relativeToURL_, "URLWithString:relativeToURL:"
	REG	S_addPeriodicTimeObserverForInterval_queue_usingBlock_, "addPeriodicTimeObserverForInterval:queue:usingBlock:"
	REG	S_addSublayer_, "addSublayer:"
	REG	S_backingScaleFactor, "backingScaleFactor"
	REG	S_begin, "begin"
	REG	S_commit, "commit"
	REG	S_currentLocale, "currentLocale"
	REG	S_localizedStringForLanguageCode_, "localizedStringForLanguageCode:"
	REG	S_preferredFrameSize, "preferredFrameSize"
	REG	S_setAlignmentMode_, "setAlignmentMode:"
	REG	S_setContentsScale_, "setContentsScale:"
	REG	S_setDisableActions_, "setDisableActions:"
	REG	S_setFontSize_, "setFontSize:"
	REG	S_setShadowOpacity_, "setShadowOpacity:"
	REG	S_setString_, "setString:"
	REG	S_setWrapped_, "setWrapped:"
	REG	S_setAffineTransform_, "setAffineTransform:"
	REG	S_setBounds_, "setBounds:"
	REG	S_setPosition_, "setPosition:"
	REG	S_setVideoGravity_, "setVideoGravity:"
	REG	S_initWithSampleBufferDisplayLayer_playbackDelegate_, "initWithSampleBufferDisplayLayer:playbackDelegate:"
	REG	S_initWithContentSource_, "initWithContentSource:"
.endm
.set Lnreg, 0
.macro REG sym, name
	.set	\sym, B_REG + 8 * Lnreg
	.set	Lnreg, Lnreg + 1
.endm
.macro REGSEL
	.set	B_SEL, B_REG + 8 * Lnreg      ; the first selector
.endm
.macro REGCLS
	.set	B_CLS, B_REG + 8 * Lnreg      ; the first class
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
	.purgem	REGCLS
	.purgem	FN
.equ B_ENG,                      B_REG + 8 * Lnreg ; the engine (media queue)
.equ E_SYNC,                     B_ENG    ; AVSampleBufferRenderSynchronizer
.equ E_AR,                       E_SYNC + 8 ; its sound renderer
.equ E_VR,                       E_AR + 8 ; and picture renderer
.equ E_SESSION,                  E_VR + 8 ; the NSURLSession; its delegate calls run on the media queue
.equ E_WAITGEN,                  E_SESSION + 8 ; w: the newest wait for a first picture
.equ E_CLR,                      E_WAITGEN + 8 ; from here, cleared when media closes
.equ E_PARENT,                   E_CLR    ; the CMBlockBuffer over the mapped file
.equ E_MAP,                      E_PARENT + 8
.equ E_LEN,                      E_MAP + 8
.equ E_VT,                       E_LEN + 8 ; the tracks playing: picture and sound
.equ E_AT,                       E_VT + 8
.equ E_DURMS,                    E_AT + 8
.equ E_MTS,                      E_DURMS + 8 ; w: movie timescale
.equ E_NTR,                      E_MTS + 4 ; w: tracks read
.equ E_HOLD,                     E_NTR + 4 ; w: the clock waits for the first picture
.equ E_WAITN,                    E_HOLD + 4 ; w: polls left
.equ E_ISO,                      E_WAITN + 4 ; w: an ISO file, not QuickTime
.equ E_GEN,                      E_ISO + 4 ; w: the play it opened
.equ E_NET,                      E_GEN + 4 ; w: the media comes as streams
.equ E_WANTV,                    E_NET + 4 ; w: a picture is coming: the clock waits for it
.equ E_TGTMS,                    E_WANTV + 4 ; the last seek's target, ms
.equ E_T0,                       E_TGTMS + 8 ; HLS: the timeline's origin in 90 kHz units (the first PTS less its segment's start), -1 unknown
.equ E_MASTER,                   E_T0 + 8  ; the master playlist and its URL
.equ E_MURL,                     E_MASTER + 8
.equ E_BPS,                      E_MURL + 8 ; the measured network speed, bits per second
.equ E_FIRSTMS,                  E_BPS + 8 ; the first picture shown after a seek, ms (+1), 0 none yet
.equ E_LIVE,                     E_FIRSTMS + 8 ; w: a YouTube broadcast: Audio Only swaps its streams
.equ E_SUBT,                     E_LIVE + 8 ; the subtitle track shown, 0 none
.equ E_SUBN,                     E_SUBT + 8 ; its next cue, taken early (retained)
.equ E_SUBEND,                   E_SUBN + 8 ; when the cue shown ends, track units
.equ E_SUBON,                    E_SUBEND + 8 ; w: a cue is shown
.equ E_CCT,                      E_SUBON + 4 + 4 ; the CC1 caption track, made when picked
.equ E_CC,                       E_CCT + 8 ; its CEA-608 decoder and the captions waiting for presentation order (CC_*)
.equ CC_MODE,                    0        ; w: 0 pop-on, 1 roll-up, 2 paint-on
.equ CC_ROWS,                    4        ; w: roll-up's rows
.equ CC_LAST,                    8        ; w: the last control pair, sent twice
.equ CC_CHAN,                    12       ; w: the channel the text is for, 1 = CC2
.equ CC_D,                       16       ; the shown caption: w length, bytes
.equ CC_N,                       CC_D + 128 ; and the one being loaded (pop-on)
.equ CC_QN,                      CC_N + 128 ; w: captions waiting, by presentation time: {pts, w pairs, pairs[8]}[6]
.equ CC_Q,                       CC_QN + 8
.equ CC_E,                       32
.equ CC_SIZE,                    CC_Q + 6 * CC_E
.equ E_ST,                       (E_CC + CC_SIZE + 63) & ~63 ; Stream[STREAMS]
.equ E_TR,                       (E_ST + STREAMS * ST_SIZE + 63) & ~63 ; Track[TRACKS]
.equ E_CLRN,                     E_TR + TRACKS * TR_SIZE - E_CLR
.equ B_RQT,                      E_TR + TRACKS * TR_SIZE ; {task, record}[RQS]: requests running (media queue)
.equ B_LTPATH,                   B_RQT + 16 * RQS ; char[1024], This Mac's file, for AVPlayer when the engine cannot play it (main)
.equ B_LTVURL,                   B_LTPATH + 1024 ; char[4096], This Mac's picture: our HLS or a broadcast's own, or "" (main)
.equ B_VISITOR,                  B_LTVURL + 4096 ; char[288], the visitorData member once YouTube gave it (lock)
.equ B_SUBL,                     B_VISITOR + 288 ; the subtitle layer, made on first use (main)
.equ B_PIC,                      B_SUBL + 8 ; w: the picture's turn, width and height, as the view lays it out (main)
.equ B_PIPE,                     B_PIC + 16 ; the engine picture's Picture in Picture controller, made on first use (main)
.equ B_AIRK,                     B_PIPE + 8 ; w: what the dormant AVPlayer would play over AirPlay: 0 nothing, 1 B_LTPATH's file, 2 its URL, 3 B_LTVURL, 4 B_AIR's TV HLS (main)
.equ B_AIR,                      B_AIRK + 8 ; a YouTube video for a TV: the picture's and sound's URLs and Fmts (main)
.equ AIR_V,                      0        ; char[4096]
.equ AIR_A,                      4096     ; char[4096]
.equ AIR_VF,                     8192     ; Fmt
.equ AIR_AF,                     AIR_VF + FMT_SIZE
.equ AIR_SIZE,                   AIR_AF + FMT_SIZE
.equ B_SIZE,                     B_AIR + AIR_SIZE
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
Ls_stream:	.asciz	"/stream/"
Ls_mp4:	.asciz	"audio/mp4"
Ls_range:	.asciz	"%lld-%lld"
Ls_200:	.asciz	"HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %lld\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
Ls_206:	.asciz	"HTTP/1.1 206 Partial Content\r\nContent-Type: %s\r\nContent-Length: %lld\r\nContent-Range: bytes %lld-%lld/%lld\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n"
Ls_404:	.asciz	"404 Not Found"
	.popsection

; ---- Small utilities ----

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

; ---- Playing a link: main -> worker -> main ----

; play_resolve(job) — resolve the link, report to main.
	ENTRY	play_resolve
	FRAME	2
	mov	x19, x0
	bl	_objc_autoreleasePoolPush
	mov	x21, x0
	mov	x0, x19
	bl	resolve
	str	w0, [x19, #JOB_RESULT]
	mov	x0, x21
	bl	_objc_autoreleasePoolPop
	adr	x0, ui_play_done
	mov	x1, x19
	bl	post_main
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

; slot_uri(text, out[256]) — serve a playlist under a fresh random token; out = its URL at loopback.
slot_uri:
	FRAME	3, 96
	mov	x19, x0
	mov	x21, x1
	mov	x0, sp                    ; 128 random bits, printed as 32 hex digits
	mov	x1, #16
	bl	_arc4random_buf
	ldp	x9, x10, [sp]
	stp	x9, x10, [sp]
	add	x0, sp, #48
	mov	x1, #TOKEN_STRIDE
	CSTR	x2, "%016llx%016llx"
	bl	_snprintf
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
	bl	_free                     ; the oldest is retired
	mov	x0, x19
	bl	_strdup
	str	x0, [x24, x23, lsl #3]
	UNLOCK
	ldr	w9, [x28, #G_PORT]
	add	x10, sp, #48
	stp	x9, x10, [sp]
	mov	x0, x21
	mov	x1, #256
	CSTR	x2, "http://127.0.0.1:%u/stream/%s.m3u8"
	bl	_snprintf
	b	Lret3

; ---- Media proxy: streams YouTube to This Mac's player ----

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

; box_find(p, end, type) — x0 = the payload of the first box of that type in [p, end), x1 = its end; x0 = 0 if none. Uses x9-x13 only.
box_find:
	add	x9, x0, #8                ; the payload, after size and type
	cmp	x9, x1
	b.hi	Lbf_none
	sub	x13, x1, x0               ; room left
	ldr	w10, [x0]
	rev	w10, w10                  ; size, big-endian
	cbnz	w10, Lbf_large
	mov	x10, x13                  ; 0: to the end
Lbf_large:
	cmp	x10, #1
	b.ne	Lbf_sized
	add	x9, x0, #16               ; 1: a 64-bit size follows the type
	cmp	x9, x1
	b.hi	Lbf_none
	ldr	x10, [x0, #8]
	rev	x10, x10
Lbf_sized:
	sub	x11, x9, x0
	cmp	x10, x11
	b.lo	Lbf_none                  ; shorter than its header
	cmp	x10, x13
	b.hi	Lbf_none                  ; past the end
	add	x11, x0, x10
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

; handle_conn(fd) — read one request and answer with the playlist its token names: the LAN server serves AirPlay receivers text only.
	.equ H_REQ,	16
	.equ H_SIZE,	H_REQ + REQ_MAX
handle_conn:
	FRAME	3, H_SIZE
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
	add	x21, x0, #1
	mov	x0, x21
	GADDR	x1, Ls_stream
	mov	x2, #8
	bl	_strncmp
	GADDR	x1, Ls_404
	cbnz	w0, Lhc_reply
	add	x21, x21, #8              ; the token
	mov	x22, #0                   ; a private copy of the text
	LOCK
	BADDR	x23, B_SLOTTOK
	add	x24, x28, #G_SLOTURL
Lhc_find:
	mov	x0, x21
	mov	x1, x23
	mov	x2, #32
	bl	_strncmp
	cbz	w0, Lhc_hit
	add	x23, x23, #TOKEN_STRIDE
	add	x24, x24, #8
	add	x9, x28, #(G_SLOTURL + 8 * SLOTS)
	cmp	x24, x9
	b.lo	Lhc_find
	b	Lhc_unlock
Lhc_hit:
	ldr	x0, [x24]
	cbz	x0, Lhc_unlock
	bl	_strdup
	mov	x22, x0
Lhc_unlock:
	UNLOCK
	GADDR	x1, Ls_404
	CSTR	x2, "unknown stream"
	cbz	x22, Lhc_reply2
	ldrb	w9, [x20]
	cmp	w9, #'H'
	cset	w2, eq                    ; HEAD: the response head only
	mov	w0, w19
	mov	x1, x22
	bl	text_stream
	mov	x0, x22
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
	b	Lret3

; server_run(fd) — accept this Mac and its LAN, one connection at a time.
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
	ccmp	w11, #0, #4, eq
	b.ne	Lsr_ok                    ; same subnet
	and	w12, w9, #0xff            ; the first octet
	cmp	w12, #127
	b.eq	Lsr_ok                    ; loopback
	bl	_close
	b	Lsr_accept
Lsr_ok:
	mov	x9, #CLIENT_TIMEOUT_S
	stp	x9, xzr, [sp]             ; struct timeval
	mov	w0, w20
	mov	w1, #SOL_SOCKET
	mov	w2, #SO_RCVTIMEO          ; a silent client cannot hold the server
	mov	x3, sp
	mov	w4, #16
	bl	_setsockopt
	mov	w0, w20
	bl	handle_conn
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
	mov	w9, #SOCKADDR_IN_HEAD
	stp	w9, wzr, [sp, #16]
	str	xzr, [sp, #24]
	add	x1, sp, #16
	mov	w2, #16
	bl	_bind                     ; every address (an AirPlay receiver fetches from the LAN one), on a port the system picks
	cbnz	w0, Lss_close
	mov	w0, w19
	mov	w1, #64
	bl	_listen
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

; api(endpoint, client, tail, frame) — POST to InnerTube as a client, into resolve's RS_BUF; w0 = 1 on success.
	.equ AP_BODY,	32
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
	stp	x25, x20, [sp]
	stp	x24, x22, [sp, #16]
	add	x0, sp, #AP_BODY
	CSTR	x1, "{\"context\":{\"client\":{%s\"hl\":\"en\",\"gl\":\"US\",\"userAgent\":\"%s\"%s}}%s"
	bl	_asprintf
	mov	w22, #0
	ldr	x9, [sp, #AP_BODY]
	cbz	x9, Lapi_free
	mov	w25, #2                   ; attempts: a kept-alive connection may have been dropped
Lapi_try:
	mov	x0, x21
	bl	mkreq
	cbz	x0, Lapi_free
	mov	x19, x0
	CSTR	x0, "POST"
	bl	mkstr
	mov	x2, x0
	mov	x0, x19
	SEND	S_setHTTPMethod_
	ldr	x0, [sp, #AP_BODY]
	bl	_strlen
	mov	x3, x0
	ldr	x2, [sp, #AP_BODY]
	CLASS	x0, NSData
	SEND	S_dataWithBytes_length_
	mov	x2, x0
	mov	x0, x19
	SEND	S_setHTTPBody_
	mov	x0, x19                   ; headers: every request's, the client's, the endpoint's field mask
	ADDR	x1, Lapi_headers
	bl	hdrs
	mov	x1, x26
	bl	hdrs
	mov	x0, x21
	bl	nextstr
	mov	x1, x0
	mov	x0, x19
	bl	hdrs
	mov	x0, x20                   ; and the client's user agent
	bl	mkstr
	mov	x22, x0
	CSTR	x0, "User-Agent"
	bl	mkstr
	mov	x3, x0
	mov	x2, x22
	mov	x0, x19
	SEND	S_setValue_forHTTPHeaderField_
	mov	x0, x19
	mov	x1, x23
	bl	fetch
	mov	w22, w0
	cbnz	w0, Lapi_free
	subs	w25, w25, #1
	b.ne	Lapi_try
Lapi_free:
	ldr	x0, [sp, #AP_BODY]
	bl	_free
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
	FRAME	4, 80                     ; the best picture's "url" value and score, its JSON span, the sound's span, the TV's picture's value, score, span
	mov	x19, x0
	mov	x20, x1
	stp	xzr, xzr, [sp]
	stp	xzr, xzr, [sp, #16]
	stp	xzr, xzr, [sp, #32]
	stp	xzr, xzr, [sp, #48]
	stp	xzr, xzr, [sp, #64]
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
	cbz	x0, Lpp_video             ; not AAC: the HLS made here carries AAC
	CSTR	x0, "\"video/mp4"
	bl	within
	cbnz	x0, Lpp_fmt
	cmp	x24, #140                 ; score: the original track 8, itag 140 4, audio only 2, no loudness compression 1
	cset	w24, eq
	lsl	w24, w24, #2
	CSTR	x0, "\"audioIsDefault\":true"
	bl	within
	cmp	x0, #0
	cset	w9, ne
	orr	w24, w24, w9, lsl #3
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
	tbnz	x24, #0, 1f               ; a TV's: the best H.264 up to 1080p
	mov	x9, #((1080 << 2) | 3)
	cmp	x24, x9
	b.hi	1f
	ldr	x9, [sp, #56]
	cmp	x24, x9
	b.le	1f
	stp	x26, x24, [sp, #48]
	stp	x21, x25, [sp, #64]
1:	ldr	x9, [sp, #8]
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
1:	ldp	x0, x1, [sp, #64]
	ADDO	x2, x19, JOB_TVFMT
	cbz	x0, 1f
	bl	fmt_info
1:	ldr	x0, [sp, #48]
	ADDO	x1, x19, JOB_TVURL
	mov	x2, #4096
	bl	jstr
	ldr	x0, [sp]
	ADDO	x1, x19, JOB_VURL
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
	mov	x0, x20                   ; artwork: the largest thumbnail YouTube lists (they grow along the list)
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
	add	x22, x0, #6
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
	GADDR	x1, Ls_sep
	bl	_strstr
	add	x9, x0, #3
	cmp	x0, #0
	csel	x23, x9, x22, ne
	mov	x0, x23
	CSTR	x1, "&?/#"
	bl	_strcspn
	add	x24, x23, x0
	mov	x0, x23
	CSTR	x1, "youtu"
	bl	_strcasestr
	cmp	x0, #0
	ccmp	x0, x24, #2, ne
	b.lo	Lrs_tube
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
	LOCK
	add	x0, sp, #RS_VIS           ; a visitorData first, as the WEB client, once per launch
	BADDR	x1, B_VISITOR
	mov	x2, #288
	bl	_strlcpy
	UNLOCK
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
	LOCK
	BADDR	x0, B_VISITOR
	add	x1, sp, #RS_VIS
	mov	x2, #288
	bl	_strlcpy
	UNLOCK
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
	ldrb	w9, [x19]
	cbnz	w9, Ltr_show
	CSTR	x22, "Beam"
Ltr_show:
	ldr	x0, [x28, #G_TITLE]
	mov	x1, x19
	bl	setstr
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
	bl	_objc_autoreleasePoolPush
	mov	x19, x0
	add	x0, x20, #ART_URL
	bl	mkreq
	cbz	x0, Laf_done
	add	x1, x20, #ART_BUF
	bl	fetch
Laf_done:
	mov	x0, x19
	bl	_objc_autoreleasePoolPop
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

; layout_stage() — between the bar and the title bar: the artwork card as large as fits (at its shape), with the note, the spinner and the link field centered on it.
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
	mov	x0, #URL_W
	mov	x1, #URL_H
	ldr	x2, [x28, #G_URLBOX]
	bl	center_box
	bl	pic_layout
	b	Lret0

; pic_layout — the engine's picture in its view: as large as fits at its shown shape, centered, turned as its track says.
pic_layout:
	FRAME	1, 80
	ldr	x19, [x28, #G_SBLAYER]
	cbz	x19, Lret1                ; not made yet
	ldr	x0, [x28, #G_SBV]
	SEND	S_bounds
	stp	d2, d3, [sp]              ; the view's width and height
	BADDR	x9, B_PIC
	ldp	w10, w11, [x9, #4]
	ucvtf	d4, w10
	ucvtf	d5, w11
	ldr	w12, [x9]
	tst	w12, #2                   ; a quarter turn: on screen, height by width
	fcsel	d6, d5, d4, ne
	fcsel	d7, d4, d5, ne
	fdiv	d16, d2, d6
	fdiv	d17, d3, d7
	fmin	d16, d16, d17             ; the scale that fits
	fmul	d6, d6, d16
	fmul	d7, d7, d16
	cmp	w10, #0
	ccmp	w11, #0, #4, ne           ; no size yet: the whole view
	fcsel	d6, d2, d6, eq
	fcsel	d7, d3, d7, eq
	tst	w12, #2
	fcsel	d4, d7, d6, ne            ; its own width and height, before the turn
	fcsel	d5, d6, d7, ne
	stp	d4, d5, [sp, #16]
	mov	w9, #1                    ; the turn's cos and sin
	cmp	w12, #180
	cneg	w9, w9, eq
	tst	w12, #2
	csel	w9, wzr, w9, ne
	asr	w10, w12, #31
	orr	w10, w10, #1
	csel	w10, w10, wzr, ne
	scvtf	d0, w9
	scvtf	d1, w10
	fneg	d2, d1
	stp	d0, d1, [sp, #32]         ; a, b, c, d (tx, ty: 0)
	stp	d2, d0, [sp, #48]
	CLASS	x0, CATransaction         ; at once
	SEND	S_begin
	CLASS	x0, CATransaction
	mov	w2, #1
	SEND	S_setDisableActions_
	movi	d0, #0
	movi	d1, #0
	ldp	d2, d3, [sp, #16]
	mov	x0, x19
	SEND	S_setBounds_
	ldp	d0, d1, [sp]
	fmov	d2, #0.5
	fmul	d0, d0, d2
	fmul	d1, d1, d2
	mov	x0, x19
	SEND	S_setPosition_
	stp	xzr, xzr, [sp, #64]
	add	x2, sp, #32
	mov	x0, x19
	SEND	S_setAffineTransform_
	CLASS	x0, CATransaction
	SEND	S_commit
	b	Lret1

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

; stage_update() — what the stage shows: This Mac's picture, else the artwork card while a track plays or loads.
stage_update:
	FRAME	2
	mov	w19, #0                   ; the picture shows
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, Lsu_pic
	ldr	w19, [x28, #G_HASVIDEO]
Lsu_pic:
	ldr	w20, [x28, #G_MODE]       ; the playing one's picture: the engine's or AVPlayer's
	cmp	w20, #0
	csel	w9, w19, wzr, eq
	eor	w2, w9, #1
	ldr	x0, [x28, #G_SBV]
	SEND	S_setHidden_
	cmp	w20, #0
	csel	w9, w19, wzr, ne
	eor	w2, w9, #1
	ldr	x0, [x28, #G_VIDEO]
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

; render_status() — the status message while it is fresh.
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

; ui_refresh(playing, position, volume, muted) — render This Mac's state and track.
ui_refresh:
	FRAME	4
	mov	w21, w0
	mov	x24, x1
	mov	w20, w2
	mov	w19, w3
	BADDR	x0, B_LTTRACK
	add	x1, x0, #T_ARTIST
	bl	show_track
	BADDR	x0, (B_LTTRACK + T_ART)
	bl	show_art
	ldr	w10, [x28, #G_PPSHOWN]
	cmp	w10, w21
	b.eq	Lur_enable
	str	w21, [x28, #G_PPSHOWN]
	ldr	x10, [x28, #G_IMGPAUSE]
	ldr	x11, [x28, #G_IMGPLAY]
	cmp	w21, #0
	csel	x2, x10, x11, ne
	ldr	x0, [x28, #G_PP]
	SEND	S_setImage_
Lur_enable:
	ldr	x25, [x28, #G_LTDUR]
	cmp	x25, #0
	cset	w26, gt                   ; seekable: with a known duration
	mov	x23, #G_BACK
Lur_each:
	ldr	x0, [x28, x23]
	mov	w2, w26
	SEND	S_setEnabled_
	add	x23, x23, #8
	cmp	x23, #G_PP
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
	scvtf	d0, w20
	ldr	x0, [x28, #G_VOL]
	SEND	S_setDoubleValue_
Lur_mute:
	ldr	w10, [x28, #G_MUTESHOWN]
	cmp	w19, w10
	b.eq	Lur_status
	str	w19, [x28, #G_MUTESHOWN]
	ldr	x10, [x28, #G_IMGMUTED]
	ldr	x11, [x28, #G_IMGUNMUTED]
	cmp	w19, #0
	csel	x2, x10, x11, ne
	ldr	x0, [x28, #G_MUTE]
	SEND	S_setImage_
Lur_status:
	bl	render_status
	bl	stage_update
	b	Lret4

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
	cmp	x19, #0
	ccmp	x20, #0, #0, le
	b.gt	Lst_now
	strb	wzr, [sp]
Lst_now:
	ldr	x0, [x28, #G_CUR]
	mov	x1, sp
	bl	setstr
	GADDR	x1, Ls_slash+1
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
	ldr	w9, [x19, #JOB_GEN]
	ldr	w10, [x28, #G_PLAYGEN]
	cmp	w9, w10
	b.ne	Lpd_free
	str	wzr, [x28, #G_LOADING]
	ldr	w20, [x19, #JOB_RESULT]
	cbnz	w20, 1f
	mov	x0, x19                   ; the engine starts first; the controls follow meanwhile
	bl	local_play
1:	ADDR	x0, Lprog_idle
	bl	ui_run
	cbnz	w20, Lpd_failed
	ADDR	x0, Lprog_played
	bl	ui_run
	GADDR	x0, Ls_slash+1
	mov	w1, #0
	bl	set_status
	b	Lpd_free
Lpd_failed:
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
	bl	set_status
Lpd_free:
	ldr	x0, [x19, #JOB_ITEM]
	SEND	S_release
	ldr	x0, [x19, #JOB_QUERY]
	bl	_free
	mov	x0, x19
	bl	_free
	bl	local_poll
	b	Lret2

; ---- This Mac: AVPlayer; macOS routes the sound to the chosen output (speakers, Bluetooth, AirPlay) ----

; local_play(job) — play on This Mac: a file with the engine, anything else with the prepared AVPlayer item.
local_play:
	FRAME	3
	mov	x19, x0
	BADDR	x0, B_LTTRACK
	add	x1, x19, #JOB_TRACK
	mov	x2, #T_SIZE
	bl	_memcpy
	ldr	x9, [x19, #JOB_DUR]
	str	x9, [x28, #G_LTDUR]
	ADDO	x1, x19, JOB_VURL         ; a broadcast's own HLS, for AirPlay
	ldr	w9, [x19, #JOB_LIVE]
	GADDR	x10, Ls_slash+1
	cmp	w9, #0
	csel	x1, x1, x10, ne
	BADDR	x0, B_LTVURL
	mov	x2, #4096
	bl	_strlcpy
	str	wzr, [x28, #G_FAILED]
	str	wzr, [x28, #G_HASVIDEO]
	str	wzr, [x28, #G_IDLE]       ; the controls stay a moment on a new track
	ldr	w9, [x19, #JOB_KIND]
	cmp	w9, #KIND_YOUTUBE
	b.ne	Llp_engine
	b	Llp_tube
	mov	w9, #1                    ; AVPlayer plays it, the engine lets go
	str	w9, [x28, #G_MODE]
	adr	x0, eng_close
	mov	x1, #0
	bl	eng_cmd
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
	b	Lret3
Llp_none:
	CSTR	x0, "Could not play this media."
	mov	w1, #1
	bl	set_status
	b	Lret3
Llp_engine:
	bl	eng_mode                  ; the engine plays a file or web media on This Mac
	ldr	w9, [x19, #JOB_KIND]
	ldr	x22, [x19, #JOB_QUERY]
	adr	x23, eng_open
	mov	w10, #1                   ; AirPlay takes the same file or URL
	cmp	w9, #KIND_FILE
	b.eq	1f
	add	x22, x19, #JOB_URL
	adr	x23, eng_web
	mov	w10, #2
1:	BADDR	x9, B_AIRK
	str	w10, [x9]
	BADDR	x0, B_LTPATH
	mov	x1, x22
	mov	x2, #1024
	bl	_strlcpy
	add	x20, x0, #1               ; the path's size
	add	x0, x0, #9
	bl	_malloc
	cbz	x0, Lret3
	ldr	w9, [x28, #G_PLAYGEN]
	str	w9, [x0]
	mov	x21, x0
	add	x0, x0, #8
	mov	x1, x22
	mov	x2, x20
	bl	_strlcpy
	mov	x0, x23
	mov	x1, x21
	bl	eng_cmd
	bl	local_poll
	b	Lret3
Llp_tube:
	BADDR	x20, B_AIR                ; for AirPlay: a broadcast's HLS, else the TV's picture with the sound
	ADDO	x1, x19, JOB_TVURL
	mov	x0, x20
	mov	x2, #4096
	bl	_strlcpy
	add	x0, x20, #AIR_A
	add	x1, x19, #JOB_URL
	mov	x2, #4096
	bl	_strlcpy
	ADDO	x0, x20, AIR_VF
	ADDO	x1, x19, JOB_TVFMT
	mov	x2, #FMT_SIZE
	bl	_memcpy
	ADDO	x0, x20, AIR_AF
	add	x1, x19, #JOB_AFMT
	mov	x2, #FMT_SIZE
	bl	_memcpy
	ldr	w9, [x19, #JOB_LIVE]
	ldrb	w10, [x20]
	cmp	w10, #0
	mov	w10, #4
	csel	w10, w10, wzr, ne
	cmp	w9, #0
	mov	w9, #3
	csel	w9, w9, w10, ne
	BADDR	x10, B_AIRK
	str	w9, [x10]
	bl	eng_mode                  ; a YouTube video: its two streams, straight to the engine
	mov	x0, #32
	bl	_malloc
	cbz	x0, Lret3
	mov	x20, x0
	ldr	w9, [x28, #G_PLAYGEN]
	str	w9, [x20, #YT_GEN]
	ldr	w9, [x19, #JOB_LIVE]
	str	w9, [x20, #YT_LIVE]
	ldr	x9, [x19, #JOB_DUR]
	mov	x10, #1000
	mul	x9, x9, x10
	str	x9, [x20, #YT_DUR]
	str	xzr, [x20, #YT_V]
	ADDO	x0, x19, JOB_VURL
	ldrb	w9, [x0]
	cbz	w9, 1f
	bl	_strdup
	str	x0, [x20, #YT_V]
1:	add	x0, x19, #JOB_URL
	bl	_strdup
	str	x0, [x20, #YT_A]
	adr	x0, eng_tube
	mov	x1, x20
	bl	eng_cmd
	bl	local_poll
	b	Lret3

; eng_mode — the engine plays: AVPlayer lets go.
eng_mode:
	FRAME	0
	str	wzr, [x28, #G_MODE]
	ldr	x0, [x28, #G_PLAYER]
	mov	x2, #0
	SEND	S_replaceCurrentItemWithPlayerItem_
	mov	w9, #1
	str	w9, [x28, #G_PLAYING]
	b	Lret0

; local_poll() — publish This Mac's playback state (its own duration and picture, once known) and re-render.
local_poll:
	FRAME	4, 48                     ; a CMTime at sp + 16
	ldr	w9, [x28, #G_MODE]
	cbz	w9, Llq_engine
	ldr	x19, [x28, #G_PLAYER]
Llq_poll:
	mov	x0, x19
	SEND	S_currentItem
	mov	x24, x0
	mov	w20, #0                   ; playing, or about to
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
	cmp	x0, #0
	cset	w20, ne
Llq_time:
	mov	x0, x19
	add	x8, sp, #16               ; a CMTime comes back through x8
	SEND	S_currentTime
	ldr	x9, [sp, #16]             ; value / timescale (0 / 0 with no item gives 0)
	ldrsw	x10, [sp, #24]
	sdiv	x21, x9, x10
Llq_show:
	str	w25, [x28, #G_HASVIDEO]
	mov	w0, w20
	mov	x1, x21
	ldr	w2, [x28, #G_VOLPCT]
	ldr	w3, [x28, #G_MUTED]
	bl	ui_refresh
	b	Lret4
Llq_engine:
	ldr	x0, [x28, #G_PLAYER]      ; AirPlay took the dormant AVPlayer to a TV: it plays on from here
	SEND	S_isExternalPlaybackActive
	cbz	w0, 1f
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_currentItem
	cbz	x0, 1f
	bl	air_handoff
	ldr	x19, [x28, #G_PLAYER]
	b	Llq_poll
1:	ldr	x9, [x27, #E_VT]          ; the picture's turn and shape, laid out when they change
	cbz	x9, 1f
	ldr	w10, [x9, #TR_ROT]
	ldr	w11, [x9, #TR_DW]
	ldr	w12, [x9, #TR_DH]
	BADDR	x13, B_PIC
	ldp	w14, w15, [x13]
	ldr	w16, [x13, #8]
	cmp	w10, w14
	ccmp	w11, w15, #0, eq
	ccmp	w12, w16, #0, eq
	b.eq	1f
	str	w10, [x13]
	stp	w11, w12, [x13, #4]
	bl	pic_layout
1:	bl	now_ms
	mov	x22, x0                   ; ms
	mov	x11, #1000
	sdiv	x21, x22, x11
	ldr	w20, [x28, #G_PLAYING]
	ldr	x9, [x27, #E_VT]
	cmp	x9, #0
	cset	w25, ne
	ldr	w9, [x27, #E_GEN]
	ldr	w10, [x28, #G_PLAYGEN]
	cmp	w9, w10
	b.ne	Llq_show                  ; still opening
	ldr	x9, [x27, #E_DURMS]
	ldr	x10, [x28, #G_LTDUR]
	udiv	x12, x9, x11
	cmp	x10, #0
	csel	x10, x12, x10, eq         ; the file's own length
	str	x10, [x28, #G_LTDUR]
	cbz	w20, Llq_efail
	cbz	x9, Llq_efail
	subs	x9, x9, x22               ; time left
	b.le	Llq_end
	cmp	x9, #1000
	b.hi	Llq_efail
	scvtf	d0, x9                    ; under a second: poll again right at the end
	ldr	s1, [x28, #G_RATE]
	fcvt	d1, s1
	fdiv	d0, d0, d1
	mov	x9, #16960                ; 1e6 ns per ms
	movk	x9, #15, lsl #16
	scvtf	d1, x9
	fmul	d0, d0, d1
	fcvtzs	x1, d0
	mov	x0, #0
	bl	_dispatch_time
	MAINQ	x1
	mov	x2, #0
	adr	x3, ui_poll
	bl	_dispatch_after_f
	b	Llq_efail
Llq_end:
	str	wzr, [x28, #G_PLAYING]    ; the end: it pauses there
	mov	w20, #0
	adr	x0, eng_rate
	mov	x1, #0
	bl	eng_cmd
Llq_efail:
	ldr	x0, [x27, #E_VR]
	SEND	S_status
	mov	x23, x0
	ldr	x0, [x27, #E_AR]
	SEND	S_status
	cmp	x0, #RENDER_FAILED
	ccmp	x23, #RENDER_FAILED, #4, ne
	b.ne	Llq_show
	ldr	w0, [x28, #G_PLAYGEN]     ; a decoder refused it: AVPlayer tries
	bl	Leng_fallback
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
	FRAME	0, 32
	ldr	w9, [x28, #G_MODE]
	cbnz	w9, Llt_av
	ldr	w9, [x28, #G_PLAYING]
	eor	w9, w9, #1
	str	w9, [x28, #G_PLAYING]
	cbz	w9, Llt_rate
	bl	now_ms                    ; played again at the end: from the start
	mov	x9, x0
	ldr	x10, [x27, #E_DURMS]
	cbz	x10, Llt_rate
	cmp	x9, x10
	b.lt	Llt_rate
	mov	x0, #0
	bl	local_seekms
	b	Lret0
Llt_rate:
	adr	x0, eng_rate
	mov	x1, #0
	bl	eng_cmd
	bl	local_poll
	b	Lret0
Llt_av:
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
	ldr	w9, [x28, #G_MODE]
	cbnz	w9, Lls_av
	str	x0, [x28, #G_SEEKTO]      ; the engine: seeks queued while one runs collapse into the newest
	add	x9, x28, #G_SEEKPEND
	mov	w10, #1
	swpal	w10, w10, [x9]
	cbnz	w10, Lls_poll
	adr	x0, eng_seekq
	mov	x1, #0
	bl	eng_cmd
Lls_poll:
	bl	local_poll
	b	Lret0
Lls_av:
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
	str	wzr, [x28, #G_PLAYING]
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_pause
	mov	x0, #0
	bl	local_seek
	b	Lret0

; local_setvol(level) — This Mac's volume, 0..100; unmutes.
local_setvol:
	str	w0, [x28, #G_VOLPCT]
	str	wzr, [x28, #G_MUTED]
	b	vol_apply

; local_volstep(delta) — change This Mac's volume by delta, within 0..100.
local_volstep:
	ldr	w9, [x28, #G_VOLPCT]
	add	w0, w9, w0
	cmp	w0, #0
	csel	w0, w0, wzr, gt
	mov	w9, #100
	cmp	w0, w9
	csel	w0, w0, w9, lt
	b	local_setvol

; local_mute() — toggle This Mac's mute.
local_mute:
	ldr	w9, [x28, #G_MUTED]
	eor	w9, w9, #1
	str	w9, [x28, #G_MUTED]
; vol_apply() — both players take G's volume and mute; then the bar shows them.
vol_apply:
	FRAME	0
	ldr	x0, [x28, #G_PLAYER]
	ldr	w9, [x28, #G_VOLPCT]
	scvtf	s0, w9
	ldr	s1, [x28, #(Lf_100 - G)]
	fdiv	s0, s0, s1
	SEND	S_setVolume_
	ldr	x0, [x28, #G_PLAYER]
	ldr	w2, [x28, #G_MUTED]
	SEND	S_setMuted_
	adr	x0, eng_vol
	mov	x1, #0
	bl	eng_cmd
	bl	local_poll
	b	Lret0

; air_prepare(self, _cmd, picker) — AirPlay's routes are shown: the dormant AVPlayer gets This Mac's media, paused, so that a picked TV takes it.
	ENTRY	air_prepare
	FRAME	1
	ldr	w9, [x28, #G_MODE]
	cbnz	w9, Lret1                 ; AVPlayer plays it already
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_currentItem
	cbnz	x0, Lret1
	BADDR	x9, B_AIRK
	ldr	w9, [x9]
	cmp	w9, #4
	b.eq	Lap_tv
	BADDR	x19, B_LTPATH
	cmp	w9, #3
	b.hi	Lret1
	b.lo	1f
	BADDR	x19, B_LTVURL             ; a broadcast's own HLS
1:	cmp	w9, #1
	b.lo	Lret1
	b.ne	2f
	mov	x0, x19                   ; a file
	bl	mkstr
	mov	x2, x0
	CLASS	x0, NSURL
	SEND	S_fileURLWithPath_
	mov	x2, x0
	CLASS	x0, AVPlayerItem
	SEND	S_playerItemWithURL_
	SEND	S_retain
	b	air_item
2:	mov	x0, x19
	bl	make_item
	b	air_item
Lap_tv:
	ldr	w9, [x28, #G_PORT]        ; YouTube: the LAN server, started on first use
	cbnz	w9, 1f
	bl	server_start
	cbz	w0, Lret1
1:	mov	x0, #(8 + AIR_SIZE)       ; the TV's HLS made on a worker, from a copy
	bl	_malloc
	cbz	x0, Lret1
	mov	x19, x0
	ldr	w9, [x28, #G_PLAYGEN]
	str	w9, [x19]
	add	x0, x19, #8
	BADDR	x1, B_AIR
	mov	x2, #AIR_SIZE
	bl	_memcpy
	WORKQ
	mov	x1, x19
	adr	x2, tv_build
	bl	_dispatch_async_f
	b	Lret1

; air_handoff — AirPlay took the dormant AVPlayer: the engine stops, AVPlayer plays on from the engine's moment, at its speed and volume.
air_handoff:
	FRAME	1
	bl	now_ms
	mov	x19, x0
	mov	w9, #1
	str	w9, [x28, #G_MODE]
	adr	x0, eng_close
	mov	x1, #0
	bl	eng_cmd
	bl	vol_apply
	mov	x0, x19
	bl	local_seekms
	ldr	w9, [x28, #G_PLAYING]
	cbz	w9, 1f
	ldr	x0, [x28, #G_PLAYER]
	ldr	s0, [x28, #G_RATE]
	SEND	S_setRate_
1:	bl	stage_update
	b	Lret1

; air_item(item) — the dormant AVPlayer holds it (retained here), silent (in a FRAME 1 of air_prepare or tv_ready).
air_item:
	cbz	x0, Lret1
	mov	x19, x0
	ldr	x0, [x28, #G_PLAYER]
	mov	w2, #1
	SEND	S_setMuted_
	ldr	x0, [x28, #G_PLAYER]
	mov	x2, x19
	SEND	S_replaceCurrentItemWithPlayerItem_
	mov	x0, x19
	SEND	S_release
	b	Lret1

; tv_ready(job) — main: the TV's HLS is served; its LAN URL (after the generation) becomes the dormant AVPlayer's item, if the media is still this one.
	ENTRY	tv_ready
	FRAME	1
	mov	x19, x0
	ldr	w9, [x19]
	ldr	w10, [x28, #G_PLAYGEN]
	ldr	w11, [x28, #G_MODE]
	cmp	w9, w10
	ccmp	w11, #0, #0, eq
	b.ne	1f
	add	x0, x19, #8
	bl	make_item
	mov	x9, x19
	mov	x19, x0
	mov	x0, x9
	bl	_free
	mov	x0, x19
	b	air_item
1:	mov	x0, x19
	bl	_free
	b	Lret1

; tv_build(job) — a worker: a YouTube video's HLS for a TV (its H.264 picture, AAC sound, segments straight from the CDN by their sidx), served on the LAN; then tv_ready with its URL.
	.equ TB_OUT,	48                ; asprintf's result
	.equ TB_V,	56                ; the picture's playlist URL [256], the sound's [256], the master's [256]
	.equ TB_A,	312
	.equ TB_M,	568
	.equ TB_SIZE,	832
	ENTRY	tv_build
	FRAME	3, TB_SIZE
	mov	x19, x0
	bl	_objc_autoreleasePoolPush
	mov	x21, x0
	add	x20, x19, #8              ; the copy
	mov	x0, x20
	ADDO	x1, x20, AIR_VF
	add	x2, sp, #TB_V
	bl	tv_media
	cbz	w0, Ltb_end
	add	x0, x20, #AIR_A
	ADDO	x1, x20, AIR_AF
	add	x2, sp, #TB_A
	bl	tv_media
	cbz	w0, Ltb_end
	add	x0, sp, #TB_A             ; the master: the picture's variant with its sound, by relative URIs
	GADDR	x1, Ls_stream
	bl	_strstr
	add	x9, x0, #8
	str	x9, [sp]
	ADDO	x9, x20, AIR_VF
	ldr	x10, [x9, #FMT_RATE]
	ADDO	x11, x20, AIR_AF
	ldr	x12, [x11, #FMT_RATE]
	add	x10, x10, x12
	add	x9, x9, #FMT_CODECS
	add	x11, x11, #FMT_CODECS
	stp	x10, x9, [sp, #8]
	str	x11, [sp, #24]
	add	x0, sp, #TB_V
	GADDR	x1, Ls_stream
	bl	_strstr
	add	x9, x0, #8
	str	x9, [sp, #32]
	add	x0, sp, #TB_OUT
	CSTR	x1, "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",NAME=\"Sound\",DEFAULT=YES,AUTOSELECT=YES,URI=\"%s\"\n#EXT-X-STREAM-INF:BANDWIDTH=%llu,CODECS=\"%s,%s\",AUDIO=\"a\"\n%s\n"
	bl	_asprintf
	tbnz	w0, #31, Ltb_end
	ldr	x0, [sp, #TB_OUT]
	add	x1, sp, #TB_M
	bl	slot_uri
	ldr	x0, [sp, #TB_OUT]
	bl	_free
	bl	discover_lan              ; for the TV: our LAN address, not loopback
	cbz	x0, Ltb_end
	and	w9, w0, #0xff
	ubfx	w10, w0, #8, #8
	ubfx	w11, w0, #16, #8
	lsr	w12, w0, #24
	stp	x9, x10, [sp]
	stp	x11, x12, [sp, #16]
	ldr	w9, [x28, #G_PORT]
	str	x9, [sp, #32]
	add	x0, sp, #TB_M
	GADDR	x1, Ls_stream
	bl	_strstr
	str	x0, [sp, #40]
	add	x0, x19, #8               ; over the copy: the job is the URL now
	mov	x1, #256
	CSTR	x2, "http://%u.%u.%u.%u:%u%s"
	bl	_snprintf
	adr	x0, tv_ready
	mov	x1, x19
	bl	post_main
	mov	x19, #0
Ltb_end:
	mov	x0, x21
	bl	_objc_autoreleasePoolPop
	mov	x0, x19
	bl	_free
	b	Lret3

; tv_media(url, fmt, out) -> w0 = 1 when a VOD playlist of the stream's segments (by its sidx) is served at out's URL.
	.equ TM_BUF,	32                ; fetch's {data, length}
	.equ TM_TXT,	48                ; the text {data, length, room}
	.equ TM_OUT,	72                ; asprintf's result
	.equ TM_OFF,	80                ; the next segment's offset
	.equ TM_SIZE,	96
tv_media:
	FRAME	4, TM_SIZE
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	mov	w22, #0
	stp	xzr, xzr, [sp, #TM_TXT]
	str	xzr, [sp, #(TM_TXT + 16)]
	stp	xzr, xzr, [sp, #TM_BUF]
	ldp	x9, x10, [x20, #FMT_IDX0]
	cbz	x10, Ltm_end
	add	x11, x10, #1
	str	x11, [sp, #TM_OFF]
	stp	x9, x10, [sp]             ; the sidx: a ranged request
	add	x0, sp, #TM_OUT
	CSTR	x1, "bytes=%llu-%llu"
	bl	_asprintf
	tbnz	w0, #31, Ltm_end
	mov	x0, x19
	bl	mkreq
	mov	x23, x0
	ldr	x0, [sp, #TM_OUT]
	bl	mkstr
	mov	x24, x0
	ldr	x0, [sp, #TM_OUT]
	bl	_free
	cbz	x23, Ltm_end
	CSTR	x0, "Range"
	bl	mkstr
	mov	x3, x0
	mov	x2, x24
	mov	x0, x23
	SEND	S_setValue_forHTTPHeaderField_
	mov	x0, x23
	add	x1, sp, #TM_BUF
	bl	fetch
	ldp	x23, x24, [sp, #TM_BUF]
	cmp	x24, #44
	b.lo	Ltm_end
	ldr	w9, [x23, #4]
	TYPE	w10, 's','i','d','x'
	cmp	w9, w10
	b.ne	Ltm_end
	ldr	w25, [x23, #16]
	rev	w25, w25                  ; timescale
	ldr	w11, [x23, #24]
	rev	w11, w11                  ; the first segment's offset past the sidx
	add	x12, x23, #30
	ldrb	w9, [x23, #8]
	cbz	w9, 1f
	ldr	x11, [x23, #28]
	rev	x11, x11
	add	x12, x23, #38
1:	ldr	x9, [sp, #TM_OFF]
	add	x9, x9, x11
	str	x9, [sp, #TM_OFF]
	ldrh	w26, [x12]
	rev16	w26, w26                  ; references
	add	x24, x12, #2
	mov	w9, #12
	umaddl	x9, w26, w9, x24
	ldr	x10, [sp, #(TM_BUF + 8)]
	add	x10, x23, x10
	cmp	x9, x10
	b.hi	Ltm_end                   ; cut short
	cbz	w25, Ltm_end
	mov	x9, x24                   ; the longest segment, for the target duration
	mov	w10, w26
	mov	w11, #0
2:	cbz	w10, 3f
	ldr	w12, [x9, #4]
	rev	w12, w12
	cmp	w12, w11
	csel	w11, w12, w11, hi
	add	x9, x9, #12
	sub	w10, w10, #1
	b	2b
3:	add	w11, w11, w25
	sub	w11, w11, #1
	udiv	w11, w11, w25
	ldr	x9, [x20, #FMT_INIT]
	add	x9, x9, #1
	stp	x11, x19, [sp]
	str	x9, [sp, #16]
	add	x0, sp, #TM_OUT
	CSTR	x1, "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:%u\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MAP:URI=\"%s\",BYTERANGE=\"%llu@0\"\n"
	bl	_asprintf
	add	x0, sp, #TM_TXT
	ldr	x1, [sp, #TM_OUT]
	bl	tm_add
Ltm_seg:
	cbz	w26, Ltm_done
	ldr	w9, [x24]
	rev	w9, w9
	and	w9, w9, #0x7fffffff       ; the segment's size
	ldr	w10, [x24, #4]
	rev	w10, w10
	ucvtf	d0, w10
	ucvtf	d1, w25
	fdiv	d0, d0, d1                ; and length, seconds
	ldr	x11, [sp, #TM_OFF]
	str	d0, [sp]
	stp	x9, x11, [sp, #8]
	str	x19, [sp, #24]
	add	x11, x11, x9
	str	x11, [sp, #TM_OFF]
	add	x0, sp, #TM_OUT
	CSTR	x1, "#EXTINF:%.3f,\n#EXT-X-BYTERANGE:%u@%llu\n%s\n"
	bl	_asprintf
	add	x0, sp, #TM_TXT
	ldr	x1, [sp, #TM_OUT]
	bl	tm_add
	add	x24, x24, #12
	sub	w26, w26, #1
	b	Ltm_seg
Ltm_done:
	add	x0, sp, #TM_TXT
	CSTR	x1, "#EXT-X-ENDLIST\n"
	mov	x2, #16                   ; with its NUL
	bl	buf_add
	ldr	x0, [sp, #TM_TXT]
	cbz	x0, Ltm_end
	mov	x1, x21
	bl	slot_uri
	mov	w22, #1
Ltm_end:
	ldr	x0, [sp, #TM_BUF]
	bl	_free
	ldr	x0, [sp, #TM_TXT]
	bl	_free
	mov	w0, w22
	b	Lret4

; tm_add(text, line) — a malloc'd line (0: none) onto a text buffer, then freed.
tm_add:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	cbz	x1, Lret2
	mov	x0, x1
	bl	_strlen
	mov	x2, x0
	mov	x0, x19
	mov	x1, x20
	bl	buf_add
	mov	x0, x20
	bl	_free
	b	Lret2
; discover_lan() -> x0 = our private IPv4 network, mask << 32 | address (en0's, else the first one; 0 without one), also into G_LAN.
discover_lan:
	FRAME	3, 16
	mov	x0, sp
	bl	_getifaddrs
	mov	x21, #0                   ; the chosen interface
	mov	x22, #0
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
	orr	x22, x20, x10, lsl #32
Ldl_free:
	ldr	x0, [sp]
	bl	_freeifaddrs
Ldl_ret:
	str	x22, [x28, #G_LAN]        ; one store: readers see a matching pair
	mov	x0, x22
	b	Lret3

; ---- Network: one NSURLSession; its delegate (the controller) runs on the media queue ----

; mkreq(url) -> an NSMutableURLRequest for a URL string (API_TIMEOUT_MS without data ends it), or nil.
mkreq:
	FRAME	0
	bl	mkurl
	cbz	x0, Lret0
	mov	x2, x0
	CLASS	x0, NSMutableURLRequest
	SEND	S_requestWithURL_
	str	x0, [sp, #-16]!
	mov	x9, #(API_TIMEOUT_MS / 1000)
	scvtf	d0, x9
	SEND	S_setTimeoutInterval_
	ldr	x0, [sp], #16
	b	Lret0

; hdrs(request, pairs) -> the request, with each name and value of a packed list as a header (an empty name ends it); x1 = what follows.
hdrs:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
Lhs_next:
	ldrb	w9, [x20]
	cbz	w9, Lhs_end
	mov	x0, x20
	bl	nextstr
	mov	x21, x0                   ; the value
	bl	mkstr
	mov	x22, x0
	mov	x0, x20
	bl	mkstr
	mov	x3, x0
	mov	x2, x22
	mov	x0, x19
	SEND	S_setValue_forHTTPHeaderField_
	mov	x0, x21
	bl	nextstr
	mov	x20, x0
	b	Lhs_next
Lhs_end:
	mov	x0, x19
	add	x1, x20, #1
	b	Lret2

; net_start(record) — start its request; the table finds the record from the task's callbacks (media queue).
	ENTRY	net_start
	FRAME	1
	mov	x19, x0
	ldr	x0, [x27, #E_SESSION]
	ldr	x2, [x19, #RQ_REQ]
	SEND	S_dataTaskWithRequest_
	cbz	x0, Lns_fail
	mov	x20, x0
	BADDR	x9, B_RQT
	mov	w10, #RQS
1:	ldr	x11, [x9]
	cbz	x11, 2f
	add	x9, x9, #16
	subs	w10, w10, #1
	b.ne	1b
Lns_fail:
	mov	x0, x19                   ; no room or no task: it failed
	mov	w1, #0
	mov	x2, #0
	ldr	x9, [x19, #RQ_DONE]
	blr	x9
	b	Lret1
2:	stp	x20, x19, [x9]
	str	x20, [x19, #RQ_TASK]
	mov	x0, x20
	SEND	S_retain
	SEND	S_resume
	b	Lret1

; rq_find(task) -> its table entry, or 0.
rq_find:
	BADDR	x9, B_RQT
	mov	w10, #RQS
1:	ldr	x11, [x9]
	cmp	x11, x0
	b.eq	2f
	add	x9, x9, #16
	subs	w10, w10, #1
	b.ne	1b
	mov	x9, #0
2:	mov	x0, x9
	ret

; rq_drop(record) — cancel its request, if running; its callbacks find nothing after this.
rq_drop:
	FRAME	1
	ldr	x19, [x0, #RQ_TASK]
	str	xzr, [x0, #RQ_TASK]
	cbz	x19, Lret1
	mov	x0, x19
	bl	rq_find
	cbz	x0, 1f
	stp	xzr, xzr, [x0]
1:	mov	x0, x19
	SEND	S_cancel
	mov	x0, x19
	SEND	S_release
	b	Lret1

; act_netdata(session, task, data) — bytes for a request: sink(record, bytes, length, task).
	ENTRY	act_netdata
	FRAME	2
	mov	x20, x4
	mov	x22, x3
	mov	x0, x3
	bl	rq_find
	cbz	x0, Lret2
	ldr	x19, [x0, #8]
	mov	x0, x20
	SEND	S_bytes
	mov	x21, x0
	mov	x0, x20
	SEND	S_length
	mov	x2, x0
	mov	x1, x21
	mov	x3, x22
	mov	x0, x19
	ldr	x9, [x19, #RQ_SINK]
	blr	x9
	b	Lret2

; act_netdone(session, task, error) — a request ended: ok for a 2xx answer without error.
	ENTRY	act_netdone
	FRAME	2
	mov	x20, x3
	mov	x21, x4
	mov	x0, x3
	bl	rq_find
	cbz	x0, Lret2
	ldr	x19, [x0, #8]
	stp	xzr, xzr, [x0]
	str	xzr, [x19, #RQ_TASK]
	mov	w22, #0
	cbnz	x21, 1f
	mov	x0, x20
	SEND	S_response
	SEND	S_statusCode
	sub	x0, x0, #200
	cmp	x0, #100
	cset	w22, lo
1:	mov	x0, x19
	mov	w1, w22
	mov	x2, x20
	ldr	x9, [x19, #RQ_DONE]
	blr	x9
	mov	x0, x20
	SEND	S_release
	b	Lret2

; sink_buf / done_sync — fetch's body grows in its buffer; its end wakes the waiting thread.
sink_buf:
	add	x3, x0, #RQ_BUF
	mov	x0, x1
	mov	x1, #1
	b	Lbuf_cb
done_sync:
	str	w1, [x0, #RQ_OK]
	ldr	x0, [x0, #RQ_SEM]
	b	_dispatch_semaphore_signal

; fetch(request, buf) — run a request from a worker thread and wait; buf {data, len} gets the body; w0 = 1 for a 2xx answer, buf empty otherwise.
fetch:
	FRAME	1, RQ_SIZE
	mov	x19, x1
	adr	x9, sink_buf
	adr	x10, done_sync
	stp	x9, x10, [sp, #RQ_SINK]
	stp	x0, xzr, [sp, #RQ_REQ]
	stp	xzr, xzr, [sp, #RQ_BUF]
	str	wzr, [sp, #RQ_OK]
	mov	x0, #0
	bl	_dispatch_semaphore_create
	str	x0, [sp, #RQ_SEM]
	adr	x0, net_start
	mov	x1, sp
	bl	eng_cmd
	ldr	x0, [sp, #RQ_SEM]
	mov	x1, #DISPATCH_TIME_FOREVER
	bl	_dispatch_semaphore_wait
	ldr	x0, [sp, #RQ_SEM]
	SEND	S_release
	ldr	w20, [sp, #RQ_OK]
	ldp	x0, x9, [sp, #RQ_BUF]
	stp	x0, x9, [x19]
	cbnz	w20, 1f
	bl	_free                     ; a failed answer's body is not kept
	stp	xzr, xzr, [x19]
1:	mov	w0, w20
	b	Lret1

; ---- Streams: media over the network, parsed as it arrives (media queue) ----

; st_pump(stream) — ask for its next bytes, unless a request runs, it ended, or every track it feeds has enough queued.
	.equ SP_URL,	16                ; char[4200]: a live segment's URL
	.equ SP_SIZE,	4224
st_pump:
	FRAME	2, SP_SIZE
	mov	x19, x0
	cbz	x19, Lret2
	ldr	x9, [x19, #ST_URL]
	ldr	x10, [x19, #ST_PLURL]
	orr	x9, x9, x10
	cbz	x9, Lret2
	ldr	w9, [x19, #ST_FETCH]
	ldr	w10, [x19, #ST_EOS]
	ldr	w11, [x19, #ST_RETRY]
	orr	w9, w9, w10
	orr	w9, w9, w11
	cbnz	w9, Lret2
	add	x20, x19, #ST_TR
	mov	w21, #2
Lpu_full:
	ldr	x9, [x20], #8
	cbz	x9, 1f
	ldr	w10, [x28, #G_AONLY]
	ldr	x11, [x27, #E_VT]
	cmp	x11, x9
	ccmp	w10, #0, #4, eq
	b.ne	1f                        ; Audio Only's picture: not waited for
	ldp	w10, w11, [x9, #TR_FH]
	sub	w10, w11, w10
	ldr	w11, [x9, #TR_KIND]
	mov	w12, #AHEAD_V
	cmp	w11, #'v'
	mov	w13, #AHEAD_A
	csel	w12, w12, w13, eq
	cmp	w11, #'s'
	mov	w13, #AHEAD_S
	csel	w12, w13, w12, eq
	cmp	w10, w12
	b.hs	Lret2                     ; enough ahead
1:	subs	w21, w21, #1
	b.ne	Lpu_full
	ldr	w9, [x19, #ST_KIND]
	cmp	w9, #1
	b.ne	2f
	mov	x0, x19                   ; HLS: its playlist and segments
	bl	hls_pump
	b	Lret2
2:	ldr	w9, [x19, #ST_FRAG]       ; a whole file read so far: nothing past its media data
	ldr	x10, [x19, #ST_MOOV]
	cmp	w9, #0
	ccmp	x10, #0, #4, eq
	b.eq	1f
	ldr	x9, [x19, #ST_POS]
	ldr	x10, [x19, #ST_MDEND]
	cmp	x9, x10
	b.hs	Lpu_end
1:	ldr	x0, [x19, #ST_URL]
	ldr	w9, [x19, #ST_LIVE]
	cbz	w9, Lpu_req
	ldr	x9, [x19, #ST_SQ]
	cbz	x9, Lpu_req               ; the first asks for the newest segment
	stp	x0, x9, [sp]
	add	x0, sp, #SP_URL
	mov	x1, #4200
	CSTR	x2, "%s&sq=%ld"
	bl	_snprintf
	add	x0, sp, #SP_URL
Lpu_req:
	bl	mkreq
	cbz	x0, Lpu_end
	mov	x20, x0
	ldr	w9, [x19, #ST_LIVE]
	cbnz	w9, Lpu_go
	ldr	x9, [x19, #ST_POS]        ; a byte range: googlevideo slows anything larger to real time
	mov	x10, #CHUNK
	add	x10, x9, x10
	sub	x10, x10, #1
	ldr	x11, [x19, #ST_LEN]
	sub	x12, x11, #1
	cmp	x11, #0
	ccmp	x10, x12, #0, ne
	csel	x10, x12, x10, hi
	stp	x9, x10, [sp]
	add	x0, sp, #SP_URL
	mov	x1, #64
	CSTR	x2, "bytes=%lld-%lld"
	bl	_snprintf
	add	x0, sp, #SP_URL
	bl	mkstr
	mov	x21, x0
	CSTR	x0, "Range"
	bl	mkstr
	mov	x3, x0
	mov	x2, x21
	mov	x0, x20
	SEND	S_setValue_forHTTPHeaderField_
Lpu_go:
	ldr	x0, [x19, #ST_URL]
	CSTR	x1, "googlevideo"
	bl	_strstr
	cbz	x0, 1f
	mov	x0, x20                   ; YouTube's CDN speaks QUIC
	mov	w2, #1
	SEND	S_setAssumesHTTP3Capable_
1:	adr	x9, st_sink
	adr	x10, st_done
	stp	x9, x10, [x19, #(ST_RQ + RQ_SINK)]
	str	x20, [x19, #(ST_RQ + RQ_REQ)]
	mov	w9, #1
	str	w9, [x19, #ST_FETCH]
	str	xzr, [x19, #ST_GOT]
	str	wzr, [x19, #ST_ANS]
	str	xzr, [x19, #ST_SKIP]
	add	x0, x19, #ST_RQ
	bl	Lnet_start
	b	Lret2
Lpu_end:
	mov	x0, x19
	bl	st_end
	b	Lret2

; st_end(stream) — no more bytes; if nothing playable came at all, AVPlayer gets the media instead.
st_end:
	mov	w9, #1
	str	w9, [x0, #ST_EOS]
	ldr	x9, [x27, #E_VT]
	ldr	x10, [x27, #E_AT]
	orr	x9, x9, x10
	cbnz	x9, 1f
	ldr	w1, [x27, #E_GEN]
	adr	x0, eng_fallback
	b	post_main
1:	ret

; st_sink(record, bytes, length, task) — a request's bytes go to the parser; an answer that is not a success is dropped.
st_sink:
	FRAME	2
	sub	x19, x0, #ST_RQ
	mov	x20, x1
	mov	x21, x2
	ldr	w9, [x19, #ST_ANS]
	cbnz	w9, 1f
	mov	w9, #1
	str	w9, [x19, #ST_ANS]
	mov	x0, x3
	SEND	S_response
	SEND	S_statusCode
	sub	x9, x0, #200
	cmp	x9, #100
	b.hs	Lsn_bad
	cmp	x0, #200
	b.ne	1f
	ldr	x9, [x19, #ST_POS]        ; the whole stream instead of the range: what lies before the position is dropped
	str	x9, [x19, #ST_SKIP]
1:	ldr	w9, [x19, #ST_ANS]
	tbnz	w9, #1, Lret2             ; refused
	ldr	x9, [x19, #ST_SKIP]
	cmp	x9, x21
	csel	x10, x9, x21, lo
	sub	x9, x9, x10
	str	x9, [x19, #ST_SKIP]
	add	x20, x20, x10
	subs	x21, x21, x10
	b.eq	Lret2
	ldr	x9, [x19, #ST_GOT]
	add	x9, x9, x21
	str	x9, [x19, #ST_GOT]
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	ldr	w9, [x19, #ST_REQT]
	cbz	w9, Lsn_bytes
	cmp	w9, #3
	b.hi	Lsn_parse                 ; an init segment: boxes
	b.lo	Lsn_text                  ; a playlist or key
	ldr	w9, [x19, #ST_ENC]
	cbnz	w9, Lsn_text              ; encrypted: decrypted whole
	bl	seg_bytes
	b	Lret2
Lsn_bytes:
	ldr	w9, [x19, #ST_KIND]
	ldr	x10, [x19, #ST_SPOS]
	orr	x9, x9, x10
	cmp	x21, #7
	ccmp	x9, #0, #0, hs
	b.ne	Lsn_parse                 ; not a stream's first bytes
	ldr	w9, [x20]
	ldur	w10, [x20, #3]
	TYPE	w11, '#','E','X','T'
	TYPE	w12, 'T','M','3','U'
	cmp	w9, w11
	ccmp	w10, w12, #0, eq
	b.ne	Lsn_box
	mov	w9, #1                    ; an HLS playlist: the stream reads its segments instead
	str	w9, [x19, #ST_KIND]
	str	w9, [x19, #ST_REQT]
	ldr	x0, [x19, #ST_URL]
	bl	_strdup
	str	x0, [x19, #ST_PLURL]
	ldr	x0, [x19, #ST_URL]
	bl	_strdup
	str	x0, [x19, #ST_RQURL]
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
Lsn_text:
	bl	txt_add
	b	Lret2
Lsn_box:
	ldr	w9, [x20, #4]             ; a box's type is four printable bytes; anything else is sound for AudioFileStream
	mov	w10, #4
1:	and	w11, w9, #0xff
	sub	w11, w11, #0x20
	cmp	w11, #0x5f
	b.hs	2f
	lsr	w9, w9, #8
	subs	w10, w10, #1
	b.ne	1b
	b	Lsn_parse
2:	bl	afs_stream
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
Lsn_parse:
	ldr	w9, [x19, #ST_KIND]
	cmp	w9, #2
	b.ne	1f
	bl	afs_sfeed
	b	Lret2
1:	bl	st_parse
	b	Lret2
Lsn_bad:
	mov	w9, #3
	str	w9, [x19, #ST_ANS]
	b	Lret2

; st_done(record, ok, task) — a request ended: on to the next bytes, a retry, or the stream's end.
st_done:
	FRAME	2
	sub	x19, x0, #ST_RQ
	mov	w20, w1
	mov	x21, x2
	str	wzr, [x19, #ST_FETCH]
	ldr	w9, [x19, #ST_KIND]
	cmp	w9, #1
	b.ne	1f
	mov	x0, x19                   ; HLS
	mov	w1, w20
	bl	hls_done
	b	Lret2
1:
	ldr	w9, [x19, #ST_LIVE]
	cbnz	w9, Lsd_live
	ldp	x9, x10, [x19, #ST_POS]   ; ST_POS, and the parsed position
	ldr	x11, [x19, #ST_GOT]
	add	x9, x9, x11
	str	x9, [x19, #ST_POS]
	cbz	w20, Lsd_fail
	cbz	x11, Lsd_end              ; nothing more
	mov	x0, x21
	SEND	S_response
	SEND	S_statusCode
	cmp	x0, #206
	b.ne	Lsd_end                   ; not a range: the whole stream came
	str	wzr, [x19, #ST_ERRS]
	ldr	x10, [x19, #ST_LEN]
	cbz	x10, 1f
	cmp	x9, x10
	b.hs	Lsd_end
1:	mov	x0, x21                   ; the CDN's redirect: later requests go straight there
	SEND	S_response
	SEND	S_URL
	SEND	S_absoluteString
	SEND	S_UTF8String
	cbz	x0, Lsd_pump
	mov	x20, x0
	ldr	x1, [x19, #ST_URL]
	bl	_strcmp
	cbz	w0, Lsd_pump
	mov	x0, x20
	bl	_strdup
	cbz	x0, Lsd_pump
	mov	x20, x0
	ldr	x0, [x19, #ST_URL]
	bl	_free
	str	x20, [x19, #ST_URL]
Lsd_pump:
	mov	x0, x19
	bl	st_pump
	b	Lret2
Lsd_live:
	cbz	w20, Lsd_fail
	str	wzr, [x19, #ST_ERRS]
	ldr	x9, [x19, #ST_SQ]
	cbnz	x9, Lsd_seg
	mov	x0, x21                   ; the newest segment's number: the next is after it
	SEND	S_response
	mov	x20, x0
	CSTR	x0, "X-Sequence-Num"
	bl	mkstr
	mov	x2, x0
	mov	x0, x20
	SEND	S_valueForHTTPHeaderField_
	SEND	S_UTF8String
	cbz	x0, Lsd_end
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	add	x0, x0, #1
	str	x0, [x19, #ST_SQ]
	b	Lsd_pump
Lsd_seg:
	ldr	x10, [x19, #ST_GOT]
	cbz	x10, Lsd_later            ; not out yet
	add	x9, x9, #1
	str	x9, [x19, #ST_SQ]
	b	Lsd_pump
Lsd_fail:
	mov	x0, x21
	SEND	S_response
	SEND	S_statusCode
	sub	x0, x0, #400
	cmp	x0, #100
	b.lo	Lsd_end                   ; refused (e.g. 416 past the end): no retry
	ldr	w9, [x19, #ST_ERRS]
	add	w9, w9, #1
	str	w9, [x19, #ST_ERRS]
	cmp	w9, #NET_TRIES
	b.hs	Lsd_end
Lsd_later:
	mov	w9, #1
	str	w9, [x19, #ST_RETRY]
	mov	x0, #0
	mov	w1, #(RETRY_NS & 0xffff)
	movk	w1, #(RETRY_NS >> 16), lsl #16
	bl	_dispatch_time
	ldr	x1, [x28, #G_MEDIAQ]
	mov	x2, x19
	adr	x3, st_retry
	bl	_dispatch_after_f
	b	Lret2
Lsd_end:
	mov	x0, x19
	bl	st_end
	b	Lret2

; st_retry(stream) — the next attempt, unless the stream was reset since.
	ENTRY	st_retry
	ldr	w9, [x0, #ST_RETRY]
	cbz	w9, 1f
	str	wzr, [x0, #ST_RETRY]
	b	st_pump
1:	ret

; st_reset(stream) — stop its request and parsing; what it fed stays queued.
st_reset:
	FRAME	1
	mov	x19, x0
	add	x0, x19, #ST_RQ
	bl	rq_drop
	ldr	x0, [x19, #ST_BBUF]
	bl	_free
	ldr	x0, [x19, #ST_ARBB]
	cbz	x0, 1f
	bl	_CFRelease                ; the arena goes with its last sample
1:	stp	xzr, xzr, [x19, #ST_BBUF]
	stp	xzr, xzr, [x19, #ST_AR]
	stp	xzr, xzr, [x19, #ST_ARPOS]
	str	xzr, [x19, #ST_ARCAP]
	stp	wzr, wzr, [x19, #ST_PST]
	stp	wzr, wzr, [x19, #ST_FETCH]
	str	wzr, [x19, #ST_ERRS]
	str	wzr, [x19, #ST_RETRY]
	b	Lret1

; st_seek(stream, ms) — its tracks drop what is queued and start again at the sync sample before that moment; a stream without its index yet starts over and seeks once it has it.
st_seek:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	bl	st_reset
	str	x20, [x19, #ST_PEND]
	add	x21, x19, #ST_TR          ; each track: its target, nothing queued
	mov	w22, #2
Lsk_tr:
	ldr	x0, [x21], #8
	cbz	x0, 1f
	mov	x1, x20
	bl	trk_target
1:	subs	w22, w22, #1
	b.ne	Lsk_tr
	ldr	w9, [x19, #ST_KIND]
	cmp	w9, #2
	b.eq	Lsk_afs
	cbnz	w9, Lsk_hls
	ldr	x9, [x19, #ST_MOOV]
	cbz	x9, Lsk_top
	ldr	w9, [x19, #ST_FRAG]
	cbz	w9, Lsk_whole
	ldr	x0, [x19, #ST_SIDX]
	cbz	x0, Lsk_top
	mov	x1, x20
	bl	sidx_find                 ; x0 = the fragment's offset from the anchor
	ldr	x9, [x19, #ST_SIDXEND]
	add	x0, x0, x9
	b	Lsk_at
Lsk_whole:
	mov	x0, x19                   ; a whole file: the cursors find the samples, the stream reads from the earliest
	bl	st_cursors
	mov	w9, #2
	str	w9, [x19, #ST_PST]
	ldr	x9, [x19, #ST_MDEND]
	sub	x9, x9, x0
	str	x9, [x19, #ST_LEFT]
	b	Lsk_go
Lsk_hls:
	str	xzr, [x19, #ST_SEQ]       ; HLS: the segment from the playlist, or when it comes
	mov	x0, x19
	bl	seg_reset
	ldr	x9, [x19, #ST_PL]
	cbz	x9, Lsk_hgo
	mov	x0, x19
	mov	w1, #1
	mov	x2, x20
	sub	sp, sp, #SG_SIZE
	mov	x3, sp
	bl	seg_scan
	ldr	x9, [sp, #SG_SEQ]
	ldr	x10, [sp, #SG_SEQ0]
	ldr	w11, [sp, #SG_N]
	add	x10, x10, w11, uxtw
	add	sp, sp, #SG_SIZE
	cmp	w0, #0
	csel	x9, x9, x10, ne           ; past the end: after the last
	str	x9, [x19, #ST_SEQ]
Lsk_hgo:
	str	wzr, [x19, #ST_EOS]
	mov	x0, x19
	bl	st_pump
	b	Lret3
Lsk_afs:
	ldr	x0, [x19, #ST_TR]         ; sound: from AudioFileStream's byte for the moment
	cbz	x0, Lsk_top
	mov	x21, x19
	mov	x19, x0
	mov	x0, x20
	bl	afs_seek
	ldr	x0, [x19, #TR_OFF]
	mov	x19, x21
	b	Lsk_at
Lsk_top:
	mov	x0, #0
Lsk_at:
	str	wzr, [x19, #ST_PST]
Lsk_go:
	str	x0, [x19, #ST_POS]
	str	x0, [x19, #ST_SPOS]
	str	xzr, [x19, #ST_EOS]
	mov	x0, x19
	bl	st_pump
	b	Lret3

; trk_target(track, ms) — the track restarts at that moment: queue emptied, earlier samples decoded only.
trk_target:
	FRAME	1
	mov	x19, x0
	mov	x9, #-1
	str	x9, [x19, #TR_APTS]       ; packed sound times itself again
	ldr	w9, [x19, #TR_TS]
	mul	x1, x1, x9
	mov	x9, #1000
	udiv	x1, x1, x9
	str	x1, [x19, #TR_TGT]
	bl	q_clear
	b	Lret1

; st_cursors(stream) -> x0 = where the stream reads from: each whole-file track at the sync sample before its target, the earliest of them.
st_cursors:
	FRAME	2
	mov	x20, x0
	mov	x21, #0x7fffffffffffffff
	add	x22, x20, #ST_TR
	ldr	x19, [x22]
	cbz	x19, 1f
	bl	trk_seek
	ldr	x9, [x19, #TR_OFF]
	cmp	x9, x21
	csel	x21, x9, x21, lo
1:	ldr	x19, [x22, #8]
	cbz	x19, 2f
	bl	trk_seek
	ldr	x9, [x19, #TR_OFF]
	cmp	x9, x21
	csel	x21, x9, x21, lo
2:	mov	x0, x21
	b	Lret2

; trk_seek — the cursor at the sync sample before the track's target (preroll for sound) (x19 = track).
trk_seek:
	FRAME	0
	ldr	x0, [x19, #TR_TGT]
	ldr	x9, [x19, #TR_SHIFT]
	add	x0, x0, x9                ; in the media's own time
	ldr	w9, [x19, #TR_KIND]
	mov	w1, #1
	cmp	w9, #'a'
	b.ne	1f
	mov	w1, #(1 + AUDIO_PREROLL)
1:	bl	cur_seek
	b	Lret0

; sidx_find(sidx, ms) -> x0 = the byte offset, from the index's anchor, of the fragment holding that moment.
sidx_find:
	ldrb	w9, [x0]                  ; version: 32- or 64-bit times and offset
	ldr	w10, [x0, #8]
	rev	w10, w10                  ; timescale
	add	x11, x0, #20
	ldr	w12, [x0, #16]
	rev	w12, w12                  ; first offset
	cbz	w9, 1f
	ldr	x12, [x0, #20]
	rev	x12, x12
	add	x11, x0, #28
1:	ldrh	w13, [x11, #2]
	rev16	w13, w13                  ; references
	add	x11, x11, #4
	mul	x1, x1, x10
	mov	x9, #1000
	udiv	x1, x1, x9                ; the moment, in the index's units
	mov	x0, x12
	mov	x14, #0                   ; time so far
2:	cbz	w13, 3f
	ldp	w9, w10, [x11], #12
	rev	w10, w10                  ; duration
	add	x15, x14, x10
	cmp	x15, x1
	b.hi	3f                        ; this one holds it
	rev	w9, w9
	and	w9, w9, #0x7fffffff
	add	x0, x0, x9
	mov	x14, x15
	sub	w13, w13, #1
	b	2b
3:	ret

; st_parse(stream, bytes, length) — boxes as they come: small ones collected and read, media data into arenas, the rest skipped.
st_parse:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
Lsp_loop:
	cbz	x21, Lret3
	ldr	w9, [x19, #ST_PST]
	cbz	w9, Lsp_head
	ldr	x22, [x19, #ST_LEFT]      ; bytes for this box in hand
	cmp	x22, x21
	csel	x22, x22, x21, lo
	cmp	w9, #2
	b.eq	Lsp_media
	b.hi	Lsp_skip
	ldp	x0, x9, [x19, #ST_BBUF]   ; 1: collected
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x22
	bl	_memcpy
	ldr	x9, [x19, #ST_BN]
	add	x9, x9, x22
	str	x9, [x19, #ST_BN]
	bl	Lsp_eat
	cbnz	x9, Lsp_loop
	mov	x0, x19
	bl	box_done
	cbz	w0, Lsp_loop
	b	Lret3                     ; the stream moved: the rest of these bytes is not wanted
Lsp_skip:
	bl	Lsp_eat
	cbnz	x9, Lsp_loop
	str	wzr, [x19, #ST_PST]       ; skipped
	b	Lsp_loop
Lsp_media:
	ldp	x9, x10, [x19, #ST_ARN]   ; ST_ARN, ST_ARCAP
	ldr	x11, [x19, #ST_AR]
	cbz	x11, 1f
	cmp	x9, x10
	b.lo	2f
1:	mov	x0, x19                   ; a new arena, from the earliest sample not yet given
	bl	arena_new
	cbz	x0, Lsp_dead
	ldp	x9, x10, [x19, #ST_ARN]
2:	sub	x10, x10, x9              ; room
	cmp	x22, x10
	csel	x22, x22, x10, lo
	ldr	x0, [x19, #ST_AR]
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x22
	bl	_memcpy
	ldr	x9, [x19, #ST_ARN]
	add	x9, x9, x22
	str	x9, [x19, #ST_ARN]
	bl	Lsp_eat
	mov	x0, x19
	bl	emit
	ldr	x9, [x19, #ST_LEFT]
	cbnz	x9, Lsp_loop
	str	wzr, [x19, #ST_PST]       ; the media data ended
	b	Lsp_loop
Lsp_dead:
	mov	x0, x19                   ; no memory: this stream stops
	bl	st_reset
	mov	w9, #1
	str	w9, [x19, #ST_EOS]
	b	Lret3
Lsp_head:
	ldr	w9, [x19, #ST_HN]
	mov	w10, #8                   ; size and type, then a 64-bit size if size is 1
	cmp	w9, #8
	b.lo	1f
	mov	w10, #16
1:	sub	w22, w10, w9
	cmp	x22, x21
	csel	x22, x22, x21, lo
	add	x0, x19, #ST_HB
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x22
	bl	_memcpy
	ldr	w9, [x19, #ST_HN]
	add	w9, w9, w22
	str	w9, [x19, #ST_HN]
	add	x20, x20, x22
	sub	x21, x21, x22
	ldr	x10, [x19, #ST_SPOS]
	add	x10, x10, x22
	str	x10, [x19, #ST_SPOS]
	cmp	w9, #8
	b.lo	Lsp_loop
	ldr	w10, [x19, #ST_HB]
	rev	w10, w10                  ; size
	mov	w11, #8
	cmp	w10, #1
	b.ne	2f
	cmp	w9, #16
	b.lo	Lsp_loop
	ldr	x10, [x19, #(ST_HB + 8)]
	rev	x10, x10
	mov	w11, #16
2:	str	wzr, [x19, #ST_HN]
	ldr	x12, [x19, #ST_SPOS]
	sub	x13, x12, x11
	str	x13, [x19, #ST_BOXPOS]
	cbnz	x10, 3f
	ldr	x10, [x19, #ST_LEN]       ; 0: to the end of the stream
	sub	x10, x10, x13
3:	subs	x10, x10, x11             ; the body
	b.lo	Lsp_bad
	str	x10, [x19, #ST_LEFT]
	ldr	w14, [x19, #(ST_HB + 4)]
	str	w14, [x19, #ST_BOXT]
	mov	w9, #3                    ; skipped, unless known
	TYPE	w15, 'm','d','a','t'
	cmp	w14, w15
	b.eq	Lsp_mdat
	TYPE	w15, 'm','o','o','v'
	cmp	w14, w15
	b.eq	Lsp_keep
	TYPE	w15, 'm','o','o','f'
	cmp	w14, w15
	b.eq	Lsp_keep
	TYPE	w15, 's','i','d','x'
	cmp	w14, w15
	b.ne	Lsp_state
Lsp_keep:
	mov	x15, #BOX_MAX
	cmp	x10, x15
	b.hi	Lsp_state
	mov	x0, x10
	bl	_malloc
	cbz	x0, Lsp_dead
	stp	x0, xzr, [x19, #ST_BBUF]
	mov	w9, #1
	ldr	x10, [x19, #ST_LEFT]
	cbnz	x10, Lsp_state
	str	wzr, [x19, #ST_PST]       ; an empty box: read now
	mov	x0, x19
	bl	box_done
	cbz	w0, Lsp_loop
	b	Lret3
Lsp_mdat:
	ldr	x9, [x19, #ST_MOOV]
	cbnz	x9, 4f
	ldr	x9, [x19, #ST_SPOS]       ; media data before the movie box: read the movie box after it first
	ldr	x10, [x19, #ST_LEFT]
	add	x9, x9, x10
	str	x9, [x19, #ST_MDEND]
	mov	x0, x19
	bl	st_reset
	ldr	x9, [x19, #ST_MDEND]
	str	x9, [x19, #ST_POS]
	str	x9, [x19, #ST_SPOS]
	mov	x0, x19
	bl	st_pump
	b	Lret3
4:	ldr	x9, [x19, #ST_SPOS]
	add	x10, x9, x10
	str	x10, [x19, #ST_MDEND]
	mov	w9, #2
Lsp_state:
	ldr	x10, [x19, #ST_LEFT]
	cmp	x10, #0
	csel	w9, wzr, w9, eq           ; an empty box: nothing to read
	str	w9, [x19, #ST_PST]
	b	Lsp_loop
Lsp_bad:
	mov	x0, x19                   ; not boxes: the stream ends
	bl	st_end
	b	Lret3
; Lsp_eat — x22 bytes of the box consumed; x9 = what is left of it.
Lsp_eat:
	add	x20, x20, x22
	sub	x21, x21, x22
	ldr	x9, [x19, #ST_SPOS]
	add	x9, x9, x22
	str	x9, [x19, #ST_SPOS]
	ldr	x9, [x19, #ST_LEFT]
	sub	x9, x9, x22
	str	x9, [x19, #ST_LEFT]
	ret

; arena_new(stream) -> x0 = 1 with a new arena for the media data, carrying over the bytes of the earliest sample not given yet; 0 without memory.
arena_new:
	FRAME	3, 16
	mov	x19, x0
	bl	st_keep                   ; x0 = the stream position still needed
	ldp	x9, x10, [x19, #ST_ARPOS]
	add	x10, x9, x10              ; the old arena's end
	ldr	x11, [x19, #ST_AR]
	ldr	x12, [x19, #ST_SPOS]
	cmp	x11, #0
	ccmp	x10, x12, #0, ne          ; its bytes carry over only if the new ones follow them
	b.ne	1f
	cmp	x0, x9
	csel	x0, x0, x9, hs
	cmp	x0, x10
	csel	x0, x0, x10, ls
	b	2f
1:	mov	x0, x12                   ; else from here
	mov	x10, x0
2:	mov	x20, x0
	sub	x21, x10, x0              ; bytes carried over
	ldr	x9, [x19, #ST_LEFT]
	mov	x10, #ARENA_MAX
	cmp	x9, x10
	csel	x9, x9, x10, lo
	add	x22, x9, x21
	mov	x0, x22
	bl	_malloc
	cbz	x0, Lan_fail
	mov	x23, x0
	cbz	x21, 3f
	ldr	x1, [x19, #ST_AR]
	ldr	x9, [x19, #ST_ARPOS]
	sub	x9, x20, x9
	add	x1, x1, x9
	mov	x2, x21
	bl	_memcpy
3:	ldr	x0, [x19, #ST_ARBB]
	cbz	x0, 4f
	bl	_CFRelease                ; the old arena goes with its last sample
4:	add	x9, x19, #ST_ARBB
	str	x9, [sp]
	mov	x0, #0
	mov	x1, x23
	mov	x2, x22
	mov	x3, #0                    ; the default allocator frees it
	mov	x4, #0
	mov	x5, #0
	mov	x6, x22
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, Lan_free
	str	x23, [x19, #ST_AR]
	stp	x20, x21, [x19, #ST_ARPOS]
	str	x22, [x19, #ST_ARCAP]
	mov	x0, #1
	b	Lret3
Lan_free:
	mov	x0, x23
	bl	_free
	str	xzr, [x19, #ST_AR]
	str	xzr, [x19, #ST_ARBB]
Lan_fail:
	mov	x0, #0
	b	Lret3

; st_keep -> x0 = the stream position of the earliest sample its tracks have not given yet (x19 = stream).
st_keep:
	mov	x0, #-1
	ldr	w9, [x19, #ST_FRAG]
	add	x10, x19, #ST_TR
	mov	w11, #2
1:	ldr	x12, [x10], #8
	cbz	x12, 4f
	cbz	w9, 2f
	ldp	w13, w14, [x12, #TR_FN]
	cmp	w14, w13
	b.hs	4f
	ldr	x15, [x12, #TR_FL]
	mov	w16, #24
	umaddl	x15, w14, w16, x15
	ldr	x15, [x15]
	b	3f
2:	ldr	w13, [x12, #TR_I]
	ldr	w14, [x12, #TR_N]
	cmp	w13, w14
	b.hs	4f
	ldr	x15, [x12, #TR_OFF]
3:	cmp	x15, x0
	csel	x0, x15, x0, lo
4:	subs	w11, w11, #1
	b.ne	1b
	ret

; emit(stream) — every sample whose bytes are all in goes to its track's queue: listed by moof boxes, or a whole file's cursors in file order.
emit:
	FRAME	2
	mov	x20, x0
	ldr	w9, [x20, #ST_FRAG]
	cbz	w9, Lem_whole
	add	x21, x20, #ST_TR
	mov	w22, #2
Lem_track:
	ldr	x19, [x21], #8
	cbz	x19, Lem_next
Lem_sample:
	ldp	w9, w10, [x19, #TR_FN]
	cmp	w10, w9
	b.hs	Lem_next
	ldr	x11, [x19, #TR_FL]
	mov	w12, #24
	umaddl	x11, w10, w12, x11        ; {offset, size, duration, composition, flags}
	ldr	x12, [x11]
	ldr	w2, [x11, #8]
	ldp	x14, x15, [x20, #ST_ARPOS]
	add	w10, w10, #1
	ldr	w5, [x11, #12]
	ldr	x3, [x19, #TR_FDTS]
	add	x16, x3, x5
	subs	x1, x12, x14
	b.lo	Lem_lost                  ; before the arena: gone
	add	x13, x1, x2
	cmp	x13, x15
	b.hi	Lem_next                  ; not all here yet
	str	w10, [x19, #TR_FI]
	str	x16, [x19, #TR_FDTS]
	bl	aonly_drop
	b.eq	Lem_sample                ; Audio Only: not this picture
	ldrsw	x9, [x11, #16]
	ldr	w6, [x11, #20]
	ldr	x10, [x19, #TR_SHIFT]
	sub	x3, x3, x10
	add	x4, x3, x9
	ubfx	w6, w6, #16, #1
	eor	w6, w6, #1                ; sample_is_non_sync_sample clear: sync
	ldr	x0, [x20, #ST_ARBB]
	bl	mk_sample
	cbz	x0, Lem_sample
	bl	q_push
	b	Lem_sample
Lem_lost:
	str	w10, [x19, #TR_FI]
	str	x16, [x19, #TR_FDTS]
	b	Lem_sample
Lem_next:
	subs	w22, w22, #1
	b.ne	Lem_track
	b	Lret2
Lem_whole:
	mov	x19, #0                   ; the track whose next sample comes first in the file
	mov	x9, #-1
	ldr	x10, [x20, #ST_TR]
	ldr	x11, [x20, #(ST_TR + 8)]
	cbz	x10, 1f
	ldr	w12, [x10, #TR_I]
	ldr	w13, [x10, #TR_N]
	cmp	w12, w13
	b.hs	1f
	ldr	x9, [x10, #TR_OFF]
	mov	x19, x10
1:	cbz	x11, 2f
	ldr	w12, [x11, #TR_I]
	ldr	w13, [x11, #TR_N]
	cmp	w12, w13
	b.hs	2f
	ldr	x12, [x11, #TR_OFF]
	cmp	x12, x9
	b.hs	2f
	mov	x19, x11
2:	cbz	x19, Lret2
	bl	cur_size
	ldr	x9, [x19, #TR_OFF]
	ldp	x14, x15, [x20, #ST_ARPOS]
	subs	x9, x9, x14
	b.lo	3f                        ; before the arena: gone
	add	x9, x9, x0
	cmp	x9, x15
	b.hi	Lret2                     ; not all here yet
	bl	aonly_drop
	b.eq	3f                        ; Audio Only: not this picture
	ldr	x0, [x20, #ST_ARBB]
	mov	x1, x14
	bl	cur_sample
	cbz	x0, Lem_whole
	bl	q_push
	b	Lem_whole
3:	bl	cur_step
	b	Lem_whole

; aonly_drop — flags eq when Audio Only drops the track's samples: it is the playing picture (x19 = track; x9, x10 only).
aonly_drop:
	ldr	w9, [x28, #G_AONLY]
	ldr	x10, [x27, #E_VT]
	cmp	x10, x19
	ccmp	w9, #0, #4, eq
	ccmp	w9, w9, #0, ne
	ret

; box_done(stream) -> w0 = 1 when reading the collected box moved the stream elsewhere.
box_done:
	FRAME	2
	mov	x19, x0
	str	wzr, [x19, #ST_PST]
	ldr	w9, [x19, #ST_BOXT]
	ldp	x20, x21, [x19, #ST_BBUF]
	str	xzr, [x19, #ST_BBUF]      ; the box is its reader's now
	TYPE	w10, 'm','o','o','v'
	cmp	w9, w10
	b.eq	Lbd_moov
	TYPE	w10, 's','i','d','x'
	cmp	w9, w10
	b.eq	Lbd_sidx
	mov	x0, x19                   ; moof
	mov	x1, x20
	mov	x2, x21
	bl	on_moof
	mov	x0, x20
	bl	_free
	mov	w0, #0
	b	Lret2
Lbd_sidx:
	ldr	x0, [x19, #ST_SIDX]
	bl	_free
	str	x20, [x19, #ST_SIDX]
	ldr	x9, [x19, #ST_SPOS]
	str	x9, [x19, #ST_SIDXEND]
	ldr	x1, [x19, #ST_PEND]
	mov	w0, #0
	cmp	x1, #0
	b.le	Lret2
	mov	x0, x19                   ; a seek waited for it
	bl	st_seek
	mov	w0, #1
	b	Lret2
Lbd_moov:
	ldr	x22, [x19, #ST_MOOV]
	cbz	x22, 1f
	ldr	w9, [x19, #ST_KIND]
	cbnz	w9, 1f                    ; HLS: another variant's init segment
	mov	x0, x20                   ; one already read (a live stream repeats it)
	bl	_free
	mov	w0, #0
	b	Lret2
1:	str	x20, [x19, #ST_MOOV]
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	bl	on_moov
	mov	w20, w0
	mov	x0, x22                   ; the tracks no longer read the old one
	bl	_free
	mov	w0, w20
	b	Lret2

; on_moov(stream, moov, length) -> w0 = 1 if the stream moved: its tracks, each fed by this stream, the first of each kind playing.
on_moov:
	FRAME	4
	mov	x20, x0
	mov	x21, x1
	add	x22, x1, x2
	mov	x0, x21
	mov	x1, x22
	TYPE	w2, 'm','v','h','d'
	bl	box_find
	cbz	x0, Lmv_traks
	add	x9, x0, #32
	cmp	x9, x1
	b.hi	Lmv_traks
	ldrb	w9, [x0]
	ldr	w10, [x0, #12]
	ldr	w11, [x0, #16]
	rev	w11, w11
	cbz	w9, 1f
	ldr	w10, [x0, #20]
	ldr	x11, [x0, #24]
	rev	x11, x11
1:	rev	w10, w10
	cbz	w10, Lmv_traks
	str	w10, [x27, #E_MTS]
	ldr	x9, [x27, #E_DURMS]
	cbnz	x9, Lmv_traks             ; YouTube said it
	mov	x12, #1000
	mul	x11, x11, x12
	udiv	x11, x11, x10
	str	x11, [x27, #E_DURMS]
Lmv_traks:
	mov	x0, x21
	mov	x1, x22
	TYPE	w2, 'm','v','e','x'
	bl	box_find
	mov	x23, x0                   ; fragmented when it has mvex
	mov	x24, x1
	cmp	x0, #0
	cset	w9, ne
	str	w9, [x20, #ST_FRAG]
	mov	x25, x21
	add	x26, x20, #ST_TR          ; tracks the stream feeds already are read again, in order
	ldr	x9, [x26]
	cmp	x9, #0
	csel	x26, x26, xzr, ne
Lmv_trak:
	mov	x0, x25
	mov	x1, x22
	TYPE	w2, 't','r','a','k'
	bl	box_find
	cbz	x0, Lmv_done
	mov	x25, x1
	ldr	w2, [x20, #ST_FRAG]
	mov	x3, #0
	cbz	x26, 1f
	add	x9, x20, #(ST_TR + 16)
	cmp	x26, x9
	b.hs	Lmv_done
	ldr	x3, [x26]
	cbz	x3, Lmv_done
1:	bl	trak_open
	cbz	x0, Lmv_trak
	mov	x19, x0
	cbz	x26, 2f
	add	x26, x26, #8
	bl	trk_aim                   ; its units may have changed
	b	3f
2:	mov	x0, x20
	bl	trk_attach
	cbz	w0, Lmv_trak
3:	cbz	x23, 4f
	mov	x0, x23
	mov	x1, x24
	bl	trex_read
4:	ldr	w9, [x20, #ST_FRAG]
	cbnz	w9, Lmv_trak
	bl	trk_seek                 ; a whole file: its cursor at the target
	b	Lmv_trak
Lmv_done:
	mov	x0, x20
	bl	no_pic
	ldr	w9, [x20, #ST_FRAG]
	cbnz	w9, Lmv_stay
	ldr	x9, [x20, #ST_MDEND]
	cbz	x9, Lmv_stay              ; the media data follows
	mov	x0, x20                   ; it came first: back to it
	ldr	x1, [x27, #E_TGTMS]
	bl	st_seek
	mov	w0, #1
	b	Lret4
Lmv_stay:
	mov	w0, #0
	b	Lret4

; trk_attach(stream) -> w0 = 1 when the track is fed by the stream, if it has room: its queue, its target; the first of its kind plays (x19 = track).
trk_attach:
	FRAME	1, 16
	mov	x20, x0
	add	x9, x20, #ST_TR
	ldr	x10, [x9]
	cbz	x10, 1f
	add	x9, x9, #8
	ldr	x10, [x9]
	cbnz	x10, Lta_no
1:	str	x9, [sp]
	mov	x0, #(FIFO_N * 8)
	bl	_malloc
	cbz	x0, Lta_no
	ldr	x9, [sp]
	str	x0, [x19, #TR_FQ]
	str	x19, [x9]
	str	x20, [x19, #TR_ST]
	mov	w9, #1
	str	w9, [x19, #TR_SRC]
	str	w9, [x19, #TR_STARVE]
	bl	trk_aim
	mov	w0, #1
	b	Lret1
Lta_no:
	mov	w0, #0
	b	Lret1

; trk_aim — the track's target from the last seek's, in its units; the first of its kind plays (x19 = track).
trk_aim:
	ldr	x1, [x27, #E_TGTMS]
	ldr	w9, [x19, #TR_TS]
	mul	x1, x1, x9
	mov	x9, #1000
	udiv	x1, x1, x9
	str	x1, [x19, #TR_TGT]
	ldr	w9, [x19, #TR_KIND]
	add	x10, x27, #((E_VT >> 12) << 12)
	add	x10, x10, #(E_VT & 4095)
	cmp	w9, #'v'
	b.eq	1f
	add	x10, x10, #(E_AT - E_VT)
	cmp	w9, #'a'
	b.ne	2f                        ; subtitles: none until picked
1:	ldr	x11, [x10]
	cbnz	x11, 2f
	str	x19, [x10]
2:	ret

; trk_new(stream, kind, timescale) -> x0 = a new track the stream feeds, or 0.
trk_new:
	FRAME	2
	mov	x20, x0
	mov	w21, w1
	mov	w22, w2
	mov	x0, #0
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Lret2
	add	w10, w9, #1
	str	w10, [x27, #E_NTR]
	BADDR	x19, E_TR
	add	x19, x19, x9, lsl #9
	stp	w21, w22, [x19, #TR_KIND]
	mov	x9, #-1
	str	x9, [x19, #TR_APTS]
	mov	x0, x20
	bl	trk_attach
	cmp	w0, #0
	csel	x0, x19, xzr, ne
	b	Lret2

; trex_read(mvex, end) — the track's fragment defaults: duration, size, flags (x19 = track).
trex_read:
	FRAME	1
	mov	x20, x1
1:	mov	x1, x20
	TYPE	w2, 't','r','e','x'
	bl	box_find
	cbz	x0, Lret1
	add	x9, x0, #24
	cmp	x9, x1
	b.hi	2f
	ldr	w9, [x0, #4]
	rev	w9, w9
	ldr	w10, [x19, #TR_ID]
	cmp	w9, w10
	b.ne	2f
	ldr	w9, [x0, #12]
	rev	w9, w9
	ldr	w10, [x0, #16]
	rev	w10, w10
	ldr	w11, [x0, #20]
	rev	w11, w11
	stp	w9, w10, [x19, #TR_DDUR]
	str	w11, [x19, #TR_DFLAGS]
	b	Lret1
2:	mov	x0, x1
	b	1b

; on_moof(stream, moof, length) — list each of its tracks' samples: offsets in the stream, sizes, durations, composition offsets, flags.
	.equ MF_DEF,	0                 ; w: duration, size, flags
	.equ MF_BASE,	16                ; the base data offset
	.equ MF_NEXT,	24                ; where the next run's data starts
	.equ MF_AT,	32                ; the next box to look at
on_moof:
	FRAME	4, 48
	mov	x20, x0
	mov	x21, x1
	add	x22, x1, x2
	mov	x23, x21                  ; the next traf
Lmf_traf:
	mov	x0, x23
	mov	x1, x22
	TYPE	w2, 't','r','a','f'
	bl	box_find
	cbz	x0, Lret4
	mov	x23, x1
	mov	x24, x0                   ; this traf
	mov	x25, x1
	TYPE	w2, 't','f','h','d'
	bl	box_find
	cbz	x0, Lmf_traf
	add	x9, x0, #8
	cmp	x9, x1
	b.hi	Lmf_traf
	ldr	w9, [x0]
	rev	w9, w9                    ; flags
	ldr	w10, [x0, #4]
	rev	w10, w10                  ; track_ID
	ldr	x19, [x20, #ST_TR]
	cbz	x19, Lmf_traf
	ldr	w11, [x19, #TR_ID]
	cmp	w11, w10
	b.eq	1f
	ldr	x19, [x20, #(ST_TR + 8)]
	cbz	x19, Lmf_traf
	ldr	w11, [x19, #TR_ID]
	cmp	w11, w10
	b.ne	Lmf_traf
1:	ldp	w12, w13, [x19, #TR_DDUR]
	ldr	w14, [x19, #TR_DFLAGS]
	ldr	x15, [x20, #ST_BOXPOS]    ; the moof's start
	add	x16, x0, #8
	tbz	w9, #0, 2f
	ldr	x15, [x16], #8
	rev	x15, x15                  ; base data offset
2:	tbz	w9, #1, 3f
	add	x16, x16, #4              ; sample description index
3:	tbz	w9, #3, 4f
	ldr	w12, [x16], #4
	rev	w12, w12
4:	tbz	w9, #4, 5f
	ldr	w13, [x16], #4
	rev	w13, w13
5:	tbz	w9, #5, 6f
	ldr	w14, [x16], #4
	rev	w14, w14
6:	cmp	x16, x1
	b.hi	Lmf_traf
	stp	w12, w13, [sp, #MF_DEF]
	str	w14, [sp, #(MF_DEF + 8)]
	stp	x15, x15, [sp, #MF_BASE]
	stp	wzr, wzr, [x19, #TR_FN]   ; a new fragment's list
	mov	x0, x24
	mov	x1, x25
	TYPE	w2, 't','f','d','t'
	bl	box_find
	cbz	x0, Lmf_runs
	add	x9, x0, #8
	cmp	x9, x1
	b.hi	Lmf_runs
	ldrb	w9, [x0]
	ldr	w10, [x0, #4]
	rev	w10, w10
	cbz	w9, 1f
	ldr	x10, [x0, #4]
	rev	x10, x10
1:	str	x10, [x19, #TR_FDTS]
	ldr	w9, [x20, #ST_KIND]
	cbz	w9, 3f
	ldr	w12, [x19, #TR_TS]        ; HLS: one timeline for every stream, anchored at the first decode time less its segment's start (90 kHz)
	mov	x13, #(90000 & 0xffff)
	movk	x13, #(90000 >> 16), lsl #16
	ldr	x11, [x27, #E_T0]
	tbz	x11, #63, 2f
	mul	x14, x10, x13
	udiv	x14, x14, x12
	ldr	x15, [x20, #ST_SEGT]
	mov	x16, #90
	msub	x11, x15, x16, x14
	str	x11, [x27, #E_T0]
2:	mul	x14, x11, x12
	sdiv	x14, x14, x13
	str	x14, [x19, #TR_SHIFT]
	b	Lmf_runs
3:	ldr	w9, [x20, #ST_LIVE]       ; live: the timeline starts at the first sample
	cbz	w9, Lmf_runs
	ldr	x9, [x19, #TR_SHIFT]
	cbnz	x9, Lmf_runs
	str	x10, [x19, #TR_SHIFT]
Lmf_runs:
	str	x24, [sp, #MF_AT]
Lmf_run:
	ldr	x0, [sp, #MF_AT]
	mov	x1, x25
	TYPE	w2, 't','r','u','n'
	bl	box_find
	cbz	x0, Lmf_traf
	str	x1, [sp, #MF_AT]
	mov	x2, sp
	bl	trun_read
	b	Lmf_run

; trun_read(trun, end, state) — append a run's samples to the track's list; state = {defaults, base, next} (x19 = track).
trun_read:
	FRAME	4
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	add	x9, x20, #8
	cmp	x9, x21
	b.hi	Lret4
	ldr	w23, [x20]
	rev	w23, w23                  ; flags
	ldr	w24, [x20, #4]
	rev	w24, w24                  ; samples
	add	x25, x20, #8
	ldr	x26, [x22, #MF_NEXT]
	tbz	w23, #0, 1f
	ldr	w9, [x25], #4
	rev	w9, w9
	sxtw	x9, w9
	ldr	x26, [x22, #MF_BASE]
	add	x26, x26, x9              ; base + data offset
1:	mov	w11, #0
	tbz	w23, #2, 2f
	ldr	w11, [x25], #4            ; the first sample's flags
	rev	w11, w11
2:	ubfx	w9, w23, #8, #4
	fmov	s0, w9
	cnt	v0.8b, v0.8b
	fmov	w9, s0
	lsl	w9, w9, #2                ; bytes per sample record
	umaddl	x10, w24, w9, x25
	cmp	x10, x21
	b.hi	Lret4                     ; cut short
	stp	w11, w9, [sp, #-16]!
	ldp	w9, w10, [x19, #TR_FN]
	ldr	w12, [x19, #TR_FCAP]
	add	w13, w9, w24
	cmp	w13, w12
	b.ls	3f
	ldr	x0, [x19, #TR_FL]         ; the list grows
	mov	w9, #24
	umull	x1, w13, w9
	str	w13, [x19, #TR_FCAP]
	bl	_realloc
	cbz	x0, Ltr_none
	str	x0, [x19, #TR_FL]
3:	ldp	w11, w9, [sp], #16
	ldr	w10, [x19, #TR_FN]
	ldr	x12, [x19, #TR_FL]
	mov	w13, #24
	umaddl	x12, w10, w13, x12        ; the first new entry
	add	w10, w10, w24
	str	w10, [x19, #TR_FN]
	mov	w13, #0                   ; sample index
Ltr_sample:
	cmp	w13, w24
	b.hs	Ltr_end
	ldr	w14, [x22, #MF_DEF]       ; duration
	ldr	w15, [x22, #(MF_DEF + 4)] ; size
	ldr	w16, [x22, #(MF_DEF + 8)] ; flags
	cbnz	w13, 4f
	tbz	w23, #2, 4f
	mov	w16, w11
4:	mov	w17, #0                   ; composition offset
	tbz	w23, #8, 5f
	ldr	w14, [x25], #4
	rev	w14, w14
5:	tbz	w23, #9, 6f
	ldr	w15, [x25], #4
	rev	w15, w15
6:	tbz	w23, #10, 7f
	ldr	w16, [x25], #4
	rev	w16, w16
7:	tbz	w23, #11, 8f
	ldr	w17, [x25], #4
	rev	w17, w17
8:	str	x26, [x12]
	stp	w15, w14, [x12, #8]
	stp	w17, w16, [x12, #16]
	add	x12, x12, #24
	add	x26, x26, x15
	add	w13, w13, #1
	b	Ltr_sample
Ltr_end:
	str	x26, [x22, #MF_NEXT]
	b	Lret4
Ltr_none:
	add	sp, sp, #16
	stp	wzr, wzr, [x19, #TR_FN]   ; no memory: the list is lost
	str	wzr, [x19, #TR_FCAP]
	str	xzr, [x19, #TR_FL]
	b	Lret4

; st_open(stream, url, live) — start a stream from its first byte (the URL is the stream's); its size from the URL's clen, if any.
st_open:
	FRAME	1
	mov	x19, x0
	str	x1, [x19, #ST_URL]
	str	w2, [x19, #ST_LIVE]
	mov	x0, x1
	CSTR	x1, "clen="
	bl	_strstr
	cbz	x0, 1f
	add	x0, x0, #5
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	str	x0, [x19, #ST_LEN]
1:	mov	x0, x19
	bl	st_pump
	b	Lret1

; st_close(stream) — stop it and free what it keeps.
st_close:
	FRAME	2
	mov	x19, x0
	bl	st_reset
	adr	x20, Lst_owned
1:	ldrh	w9, [x20], #2
	cmp	w9, #1
	b.eq	Lret2                     ; the end mark (0 is ST_URL)
	ldr	x0, [x19, x9]
	str	xzr, [x19, x9]            ; it may open again
	bl	_free
	b	1b
Lst_owned:	                          ; what a stream allocates
	.short	ST_URL, ST_MOOV, ST_SIDX, ST_TXT, ST_PLURL, ST_PL, ST_KEYURL, ST_MAPURL, ST_RQURL, ST_VPES, ST_APES, ST_VPEN, 1
	.p2align 2

; ---- HLS: playlists, their segments (TS, fMP4, packed audio), the variant the network allows (media queue) ----

; line_end(p) -> x0 = the end of p's line, less trailing white space; x1 = the next line.
line_end:
	mov	x9, x0
1:	ldrb	w10, [x9]
	cbz	w10, 2f
	cmp	w10, #'\n'
	b.eq	2f
	add	x9, x9, #1
	b	1b
2:	mov	x1, x9
	cbz	w10, 3f
	add	x1, x9, #1
3:	cmp	x9, x0
	b.ls	4f
	ldurb	w10, [x9, #-1]
	cmp	w10, #' '
	b.hi	4f
	sub	x9, x9, #1
	b	3b
4:	mov	x0, x9
	ret

; attr(line, end, name) -> x0 = name's value in [line, end), without quotes, x1 = its end; x0 = 0 if absent (name ends with '=').
attr:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	mov	x0, x2
	bl	_strlen
	mov	x22, x0
La_find:
	mov	x0, x19
	mov	x1, x21
	sub	x2, x20, x19
	bl	_strnstr
	cbz	x0, Lret2
	add	x19, x0, #1               ; inside a longer name: look again after it
	ldurb	w9, [x0, #-1]
	mov	w10, #','
	cmp	w9, #':'
	ccmp	w9, w10, #4, ne
	b.ne	La_find
	add	x0, x0, x22
	mov	x1, x0
	ldrb	w9, [x0]
	cmp	w9, #'"'
	b.ne	La_bare
	add	x0, x0, #1
	mov	x1, x0
1:	cmp	x1, x20
	b.hs	Lret2
	ldrb	w9, [x1]
	cmp	w9, #'"'
	b.eq	Lret2
	add	x1, x1, #1
	b	1b
La_bare:
	cmp	x1, x20
	b.hs	Lret2
	ldrb	w9, [x1]
	cmp	w9, #','
	b.eq	Lret2
	add	x1, x1, #1
	b	La_bare

; attr_num(line, name) -> x0 = name's decimal value in the line, 0 if absent.
attr_num:
	FRAME	1
	mov	x19, x0
	mov	x20, x1
	bl	line_end
	mov	x1, x0
	mov	x0, x19
	mov	x2, x20
	bl	attr
	cbz	x0, Lret1
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	b	Lret1

; seg_scan(stream, mode, value, out) -> w0 = 1 with out the media playlist's segment: mode 0 by media sequence number, 1 by time (ms); out's playlist fields are filled either way.
seg_scan:
	FRAME	4, 16
	mov	x19, x3
	mov	w20, w1
	mov	x21, x2
	ldr	x22, [x0, #ST_PL]
	mov	x0, x19
	mov	x1, #SG_SIZE
	bl	_bzero
	str	xzr, [sp]                 ; where a range without offset starts
	mov	x23, #0                   ; time so far
	mov	x24, #0                   ; the coming segment's duration
	mov	w26, #0                   ; segments passed
	cbz	x22, Lsg_none
Lsg_line:
	ldrb	w9, [x22]
	cbz	w9, Lsg_none
	cmp	w9, #'#'
	b.eq	Lsg_tag
	cmp	w9, #' '
	b.ls	Lsg_next
	ldr	x9, [x19, #SG_SEQ0]       ; a segment's URI
	add	x9, x9, w26, uxtw
	cbnz	w20, 1f
	cmp	x9, x21
	b.eq	Lsg_hit
	b	Lsg_pass
1:	add	x10, x23, x24
	cmp	x10, x21
	b.gt	Lsg_hit
Lsg_pass:
	add	w26, w26, #1
	add	x23, x23, x24
	mov	x24, #0
	ldp	x10, x11, [x19, #SG_BRL]
	add	x10, x10, x11
	str	x10, [sp]
	str	xzr, [x19, #SG_BRL]
	str	wzr, [x19, #SG_DISC]
	b	Lsg_next
Lsg_hit:
	str	x9, [x19, #SG_SEQ]
	str	x22, [x19, #SG_URI]
	mov	x0, x22
	bl	line_end
	str	x0, [x19, #SG_URIE]
	stp	x23, x24, [x19, #SG_T]
	str	w26, [x19, #SG_N]
	mov	w0, #1
	b	Lret4
Lsg_tag:
	ldrb	w9, [x22, #4]
	cmp	w9, #'I'
	b.eq	Lsg_inf                   ; #EXTINF:
	cmp	w9, #'-'
	b.ne	Lsg_next
	ldrh	w9, [x22, #7]             ; #EXT-X-...
	mov	w10, #('B' | 'Y' << 8)    ; BYTERANGE, not BITRATE
	cmp	w9, w10
	b.eq	Lsg_br
	and	w9, w9, #0xff
	cmp	w9, #'K'
	b.eq	Lsg_key
	cmp	w9, #'T'
	b.eq	Lsg_tdur
	cmp	w9, #'E'
	b.eq	Lsg_end
	cmp	w9, #'D'
	b.eq	Lsg_disc
	cmp	w9, #'M'
	b.ne	Lsg_next
	ldrb	w9, [x22, #8]
	cmp	w9, #'A'
	b.eq	Lsg_map
	add	x0, x22, #22              ; #EXT-X-MEDIA-SEQUENCE:
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	str	x0, [x19, #SG_SEQ0]
	b	Lsg_next
Lsg_inf:
	add	x0, x22, #8
	mov	x1, #0
	bl	_strtod
	mov	x9, #1000
	scvtf	d1, x9
	fmul	d0, d0, d1
	fcvtzs	x24, d0
	b	Lsg_next
Lsg_br:
	add	x0, x22, #17              ; #EXT-X-BYTERANGE:n[@o]
	add	x1, sp, #8
	mov	w2, #10
	bl	_strtol
	str	x0, [x19, #SG_BRL]
	ldr	x11, [sp]
	ldr	x9, [sp, #8]
	ldrb	w10, [x9]
	cmp	w10, #'@'
	b.ne	1f
	add	x0, x9, #1
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	mov	x11, x0
1:	str	x11, [x19, #SG_BRO]
	b	Lsg_next
Lsg_key:
	add	x0, x22, #11              ; #EXT-X-KEY:METHOD=NONE ends encryption
	CSTR	x1, "METHOD=NONE"
	mov	x2, #11
	bl	_strncmp
	cmp	w0, #0
	csel	x9, xzr, x22, eq
	str	x9, [x19, #SG_KEY]
	b	Lsg_next
Lsg_map:
	str	x22, [x19, #SG_MAP]
	b	Lsg_next
Lsg_tdur:
	add	x0, x22, #22
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	mov	x9, #1000
	mul	x0, x0, x9
	str	w0, [x19, #SG_TDUR]
	b	Lsg_next
Lsg_end:
	mov	w9, #1
	str	w9, [x19, #SG_END]
	b	Lsg_next
Lsg_disc:
	ldrb	w9, [x22, #20]
	cmp	w9, #'-'
	b.eq	Lsg_next                  ; DISCONTINUITY-SEQUENCE
	mov	w9, #1
	str	w9, [x19, #SG_DISC]
Lsg_next:
	mov	x0, x22
	bl	line_end
	mov	x22, x1
	b	Lsg_line
Lsg_none:
	str	w26, [x19, #SG_N]
	str	x23, [x19, #SG_T]         ; the playlist's length
	mov	w0, #0
	b	Lret4

; url_join(base, uri, end) -> x0 = the absolute URL (malloc) of a URI in [uri, end), relative to base; 0 if not one.
	.equ UJ_BUF,	4112
url_join:
	FRAME	1, UJ_BUF
	mov	x19, x0
	sub	x2, x2, x1
	mov	x9, #4095
	cmp	x2, x9
	csel	x2, x2, x9, lo
	add	x2, x2, #1
	mov	x0, sp
	bl	_strlcpy
	mov	x0, x19
	bl	mkurl
	mov	x19, x0
	mov	x0, sp
	bl	mkstr
	mov	x2, x0
	mov	x3, x19
	CLASS	x0, NSURL
	SEND	S_URLWithString_relativeToURL_
	SEND	S_absoluteString
	SEND	S_UTF8String
	cbz	x0, Lret1
	bl	_strdup
	b	Lret1

; hls_pick() -> w0 = 1 with the master playlist's variant for the measured speed as the first stream's playlist, and the first time its sound rendition as the second's.
hls_pick:
	FRAME	4, 16
	ldr	x9, [x27, #E_BPS]
	mov	x23, #(BPS_START & 0xffff)
	movk	x23, #(BPS_START >> 16), lsl #16
	cbz	x9, 1f
	mov	x10, #5
	udiv	x23, x9, x10
	lsl	x23, x23, #2              ; four fifths of it
1:	ldr	x19, [x27, #E_MASTER]
	mov	x20, #0                   ; the best line that fits, and its bandwidth
	mov	x21, #0
	mov	x22, #0                   ; the lowest, and its bandwidth
	mov	x24, #-1
	mov	x0, x19
	CSTR	x1, "mp4a.40.2"
	bl	_strstr
	str	x0, [sp]                  ; the master lists AAC-LC
Lpk_line:
	ldrb	w9, [x19]
	cbz	w9, Lpk_done
	mov	x0, x19
	CSTR	x1, "#EXT-X-STREAM-INF:"
	mov	x2, #18
	bl	_strncmp
	cbnz	w0, Lpk_next
	ldr	x9, [sp]
	cbz	x9, 6f
	mov	x0, x19                   ; AAC-LC variants only, when there are any
	bl	line_end
	sub	x2, x0, x19
	mov	x0, x19
	CSTR	x1, "mp4a.40.2"
	bl	_strnstr
	cbz	x0, Lpk_next
6:	mov	x0, x19
	CSTR	x1, "BANDWIDTH="
	bl	attr_num
	cmp	x0, x24
	b.hs	1f
	mov	x24, x0
	mov	x22, x19
1:	cmp	x0, x23
	ccmp	x0, x21, #0, ls
	b.ls	Lpk_next
	mov	x21, x0
	mov	x20, x19
Lpk_next:
	mov	x0, x19
	bl	line_end
	mov	x19, x1
	b	Lpk_line
Lpk_done:
	cmp	x20, #0
	csel	x20, x22, x20, eq         ; none fits: the lowest
	mov	w0, #0
	cbz	x20, Lret4
	mov	x0, x20                   ; its URI: the next line that is not a tag
	bl	line_end
	mov	x19, x1
2:	ldrb	w9, [x19]
	cbz	w9, Lpk_no
	mov	w10, #' '
	cmp	w9, #'#'
	ccmp	w9, w10, #0, ne
	b.hi	3f
	mov	x0, x19
	bl	line_end
	mov	x19, x1
	b	2b
3:	mov	x0, x19
	bl	line_end
	mov	x2, x0
	ldr	x0, [x27, #E_MURL]
	mov	x1, x19
	bl	url_join
	cbz	x0, Lpk_no
	BADDR	x21, E_ST
	mov	x1, x0
	mov	x0, x21
	bl	pl_set
	ldr	w9, [x27, #(E_ST + ST_SIZE + ST_KIND)]
	cbnz	w9, Lpk_yes               ; the sound rendition was chosen already
	mov	x0, x20                   ; its sound: AUDIO="group" names an EXT-X-MEDIA with a URI
	bl	line_end
	mov	x1, x0
	mov	x0, x20
	CSTR	x2, "AUDIO="
	bl	attr
	cbz	x0, Lpk_yes
	mov	x23, x0
	sub	x24, x1, x0               ; the group's name and length
	ldr	x19, [x27, #E_MASTER]
	mov	x22, #0                   ; the rendition chosen
Lpk_media:
	ldrb	w9, [x19]
	cbz	w9, Lpk_found
	mov	x0, x19
	CSTR	x1, "#EXT-X-MEDIA:"
	mov	x2, #13
	bl	_strncmp
	cbnz	w0, Lpk_mnext
	mov	x0, x19
	bl	line_end
	mov	x20, x0
	mov	x0, x19
	CSTR	x1, "TYPE=AUDIO"
	sub	x2, x20, x19
	bl	_strnstr
	cbz	x0, Lpk_mnext
	mov	x1, x20
	mov	x0, x19
	CSTR	x2, "GROUP-ID="
	bl	attr
	cbz	x0, Lpk_mnext
	sub	x9, x1, x0
	cmp	x9, x24
	b.ne	Lpk_mnext
	mov	x1, x23
	mov	x2, x24
	bl	_strncmp
	cbnz	w0, Lpk_mnext
	mov	x0, x19
	mov	x1, x20
	CSTR	x2, "URI="
	bl	attr
	cbz	x0, Lpk_mnext             ; in the variant's own segments
	cbnz	x22, 4f
	mov	x22, x19                  ; the first, unless a default follows
4:	mov	x0, x19
	CSTR	x1, "DEFAULT=YES"
	sub	x2, x20, x19
	bl	_strnstr
	cbz	x0, Lpk_mnext
	mov	x22, x19
	b	Lpk_found
Lpk_mnext:
	mov	x0, x19
	bl	line_end
	mov	x19, x1
	b	Lpk_media
Lpk_found:
	cbz	x22, Lpk_yes
	mov	x0, x22
	bl	line_end
	mov	x1, x0
	mov	x0, x22
	CSTR	x2, "URI="
	bl	attr
	mov	x2, x1
	mov	x1, x0
	ldr	x0, [x27, #E_MURL]
	bl	url_join
	cbz	x0, Lpk_yes
	mov	x1, x0
	BADDR	x0, (E_ST + ST_SIZE)
	bl	pl_set
Lpk_yes:
	mov	w0, #1
	b	Lret4
Lpk_no:
	mov	w0, #0
	b	Lret4

; pl_set(stream, url) — the stream plays that media playlist (the URL becomes its); a new one is loaded at the next segment.
pl_set:
	FRAME	1
	mov	x19, x0
	mov	x20, x1
	ldr	x0, [x19, #ST_PLURL]
	cbz	x0, 1f
	mov	x1, x20
	bl	_strcmp
	cbnz	w0, 1f
	mov	x0, x20                   ; the same one
	bl	_free
	b	Lret1
1:	ldr	x0, [x19, #ST_PLURL]
	bl	_free
	str	x20, [x19, #ST_PLURL]
	mov	w9, #1
	str	w9, [x19, #ST_KIND]
	str	w9, [x19, #ST_STALE]
	b	Lret1

; st_get(stream, url, type, first, length) — request a URL for the stream (type: ST_REQT); bytes from first, length of them (0: all, or CHUNK of a stream's bytes).
	.equ GT_BUF,	16
st_get:
	FRAME	3, 80
	mov	x19, x0
	mov	w22, w2
	mov	x23, x3
	mov	x24, x4
	str	w2, [x19, #ST_REQT]
	mov	x0, x1
	bl	mkreq
	cbz	x0, Lgt_fail
	mov	x20, x0
	cbnz	x24, 1f
	cbnz	w22, Lgt_go               ; a whole text or segment
	mov	x24, #CHUNK               ; a stream's bytes: googlevideo slows anything larger to real time
	ldr	x11, [x19, #ST_LEN]
	sub	x12, x11, x23
	cmp	x11, #0
	ccmp	x24, x12, #0, ne
	csel	x24, x12, x24, hi
1:	add	x10, x23, x24
	sub	x10, x10, #1
	stp	x23, x10, [sp]
	add	x0, sp, #GT_BUF
	mov	x1, #64
	CSTR	x2, "bytes=%lld-%lld"
	bl	_snprintf
	add	x0, sp, #GT_BUF
	bl	mkstr
	mov	x21, x0
	CSTR	x0, "Range"
	bl	mkstr
	mov	x3, x0
	mov	x2, x21
	mov	x0, x20
	SEND	S_setValue_forHTTPHeaderField_
Lgt_go:
	mov	x0, x20
	SEND	S_URL
	SEND	S_absoluteString
	SEND	S_UTF8String
	CSTR	x1, "googlevideo"
	bl	_strstr
	cbz	x0, 2f
	mov	x0, x20                   ; YouTube's CDN speaks QUIC
	mov	w2, #1
	SEND	S_setAssumesHTTP3Capable_
2:	adr	x9, st_sink
	adr	x10, st_done
	stp	x9, x10, [x19, #(ST_RQ + RQ_SINK)]
	str	x20, [x19, #(ST_RQ + RQ_REQ)]
	mov	w9, #1
	str	w9, [x19, #ST_FETCH]
	str	xzr, [x19, #ST_GOT]
	str	wzr, [x19, #ST_ANS]
	str	xzr, [x19, #ST_SKIP]
	str	xzr, [x19, #ST_TXTN]
	mov	w0, #CLOCK_UPTIME_RAW
	bl	_clock_gettime_nsec_np
	str	x0, [x19, #ST_T1]
	add	x0, x19, #ST_RQ
	bl	Lnet_start
	b	Lret3
Lgt_fail:
	mov	x0, x19
	bl	st_end
	b	Lret3

; st_get_own(stream, url, type, first, length) — st_get with a URL (malloc) the stream keeps until its next request.
st_get_own:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	mov	w21, w2
	mov	x22, x3
	mov	x23, x4
	ldr	x0, [x19, #ST_RQURL]
	bl	_free
	str	x20, [x19, #ST_RQURL]
	mov	x0, x19
	mov	x1, x20
	mov	w2, w21
	mov	x3, x22
	mov	x4, x23
	bl	st_get
	b	Lret3

; st_later(ms, stream) — st_pump for the stream after half that long: a retry, or a live playlist's reload.
st_later:
	FRAME	1
	mov	x19, x1
	mov	w9, #1
	str	w9, [x19, #ST_RETRY]
	mov	w9, #(500000 & 0xffff)
	movk	w9, #(500000 >> 16), lsl #16
	umull	x1, w0, w9
	mov	x0, #0
	bl	_dispatch_time
	ldr	x1, [x28, #G_MEDIAQ]
	mov	x2, x19
	adr	x3, st_retry
	bl	_dispatch_after_f
	b	Lret1

; seg_reset(stream) — a new segment: no partial TS packet or PES, the box parser at a box.
seg_reset:
	str	xzr, [x0, #(ST_VPEN + 8)]
	str	wzr, [x0, #ST_TSN]
	str	xzr, [x0, #(ST_VPES + 8)]
	str	xzr, [x0, #(ST_APES + 8)]
	str	wzr, [x0, #ST_PST]
	str	wzr, [x0, #ST_HN]
	ret

; hexbyte(hi, lo) -> w9 = the byte two hex digits spell (w9, w10 in).
hexbyte:
	orr	w9, w9, #0x20
	orr	w10, w10, #0x20
	sub	w9, w9, #'0'
	cmp	w9, #10
	b.lo	1f
	sub	w9, w9, #('a' - '0' - 10)
1:	sub	w10, w10, #'0'
	cmp	w10, #10
	b.lo	2f
	sub	w10, w10, #('a' - '0' - 10)
2:	orr	w9, w10, w9, lsl #4
	ret

; hls_pump(stream) — an HLS stream's next request: its playlist when due, the segment's key or init segment once, then the segment.
	.equ HP_SEG,	16
	.equ HP_SIZE,	HP_SEG + SG_SIZE
hls_pump:
	FRAME	3, HP_SIZE
	mov	x19, x0
	ldr	x9, [x19, #ST_PL]
	ldr	w10, [x19, #ST_STALE]
	cmp	x9, #0
	ccmp	w10, #0, #0, ne
	b.ne	Lhp_list
	mov	x0, x19
	mov	w1, #0
	ldr	x2, [x19, #ST_SEQ]
	add	x3, sp, #HP_SEG
	bl	seg_scan
	cbnz	w0, Lhp_seg
	ldr	x9, [sp, #(HP_SEG + SG_SEQ0)]
	ldr	x10, [x19, #ST_SEQ]
	cmp	x10, x9
	b.lo	Lhp_behind
	ldr	w9, [sp, #(HP_SEG + SG_END)]
	cbnz	w9, Lhp_end
	mov	w9, #1                    ; live, not out yet: the playlist again in half a target duration
	str	w9, [x19, #ST_STALE]
	ldr	w0, [sp, #(HP_SEG + SG_TDUR)]
	mov	x1, x19
	bl	st_later
	b	Lret3
Lhp_behind:
	str	x9, [x19, #ST_SEQ]        ; out of the live window: its oldest
	mov	x0, x19
	bl	hls_pump
	b	Lret3
Lhp_end:
	mov	x0, x19
	bl	st_end
	b	Lret3
Lhp_list:
	str	wzr, [x19, #ST_STALE]
	ldr	x0, [x19, #ST_PLURL]
	bl	_strdup
	mov	x1, x0
	mov	x0, x19
	mov	w2, #1
	mov	x3, #0
	mov	x4, #0
	bl	st_get_own
	b	Lret3
Lhp_seg:
	ldr	x9, [sp, #(HP_SEG + SG_T)]
	str	x9, [x19, #ST_SEGT]
	ldr	w9, [sp, #(HP_SEG + SG_DISC)]
	cbz	w9, 1f
	mov	x9, #-1                   ; a discontinuity: the timeline is anchored again
	str	x9, [x27, #E_T0]
1:	str	wzr, [x19, #ST_ENC]
	ldr	x20, [sp, #(HP_SEG + SG_KEY)]
	cbz	x20, Lhp_map
	mov	x0, x20                   ; AES-128: its key, fetched once
	bl	line_end
	mov	x21, x0
	mov	x1, x0
	mov	x0, x20
	CSTR	x2, "URI="
	bl	attr
	cbz	x0, Lhp_map
	mov	x2, x1
	mov	x1, x0
	ldr	x0, [x19, #ST_PLURL]
	bl	url_join
	cbz	x0, Lhp_map
	mov	x22, x0
	ldr	x1, [x19, #ST_KEYURL]
	cbz	x1, 2f
	bl	_strcmp
	cbz	w0, 3f
2:	mov	x0, x19
	mov	x1, x22
	mov	w2, #2
	mov	x3, #0
	mov	x4, #0
	bl	st_get_own
	b	Lret3
3:	mov	x0, x22
	bl	_free
	mov	w9, #1
	str	w9, [x19, #ST_ENC]
	ldr	x9, [x19, #ST_SEQ]        ; its IV: given, else the media sequence number
	rev	x9, x9
	stp	xzr, x9, [x19, #ST_IV]
	mov	x0, x20
	mov	x1, x21
	CSTR	x2, "IV="
	bl	attr
	cbz	x0, Lhp_map
	add	x11, x0, #2               ; 0x and 32 hex digits
	add	x12, x19, #ST_IV
	mov	w13, #16
4:	ldrb	w9, [x11], #1
	ldrb	w10, [x11], #1
	bl	hexbyte
	strb	w9, [x12], #1
	subs	w13, w13, #1
	b.ne	4b
Lhp_map:
	ldr	x20, [sp, #(HP_SEG + SG_MAP)]
	cbz	x20, Lhp_get
	mov	x0, x20                   ; fMP4: its init segment, read once
	bl	line_end
	mov	x21, x0
	mov	x1, x0
	mov	x0, x20
	CSTR	x2, "URI="
	bl	attr
	cbz	x0, Lhp_get
	mov	x2, x1
	mov	x1, x0
	ldr	x0, [x19, #ST_PLURL]
	bl	url_join
	cbz	x0, Lhp_get
	mov	x22, x0
	ldr	x1, [x19, #ST_MAPURL]
	cbz	x1, 5f
	bl	_strcmp
	cbz	w0, 6f
5:	mov	x0, x20                   ; its range, if given: "n@o"
	mov	x1, x21
	CSTR	x2, "BYTERANGE="
	bl	attr
	mov	x3, #0
	mov	x4, #0
	cbz	x0, 7f
	add	x1, sp, #(HP_SEG + SG_BRL)
	mov	w2, #10
	bl	_strtol
	mov	x4, x0
	mov	x3, #0
	ldr	x9, [sp, #(HP_SEG + SG_BRL)]
	ldrb	w10, [x9]
	cmp	w10, #'@'
	b.ne	7f
	str	x4, [sp, #(HP_SEG + SG_BRO)]
	add	x0, x9, #1
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	mov	x3, x0
	ldr	x4, [sp, #(HP_SEG + SG_BRO)]
7:	str	wzr, [x19, #ST_PST]
	str	wzr, [x19, #ST_HN]
	mov	x0, x19
	mov	x1, x22
	mov	w2, #4
	bl	st_get_own
	b	Lret3
6:	mov	x0, x22
	bl	_free
Lhp_get:
	str	wzr, [x19, #ST_SEGF]
	mov	x0, x19
	bl	seg_reset
	ldr	x0, [x19, #ST_PLURL]
	ldp	x1, x2, [sp, #(HP_SEG + SG_URI)]
	bl	url_join
	cbz	x0, Lhp_end
	mov	x1, x0
	mov	x0, x19
	mov	w2, #3
	ldp	x4, x3, [sp, #(HP_SEG + SG_BRL)]
	bl	st_get_own
	b	Lret3

; hls_text(stream) — a playlist or key came whole: a master picks its variant and sound, a media playlist replaces the last (the first sets where to start), a key is kept.
	.equ HT_SEG,	0
hls_text:
	FRAME	2, SG_SIZE
	mov	x19, x0
	ldr	x20, [x19, #ST_TXT]
	stp	xzr, xzr, [x19, #ST_TXT]  ; the text is its reader's now
	cbz	x20, Lret2
	ldr	w9, [x19, #ST_REQT]
	cmp	w9, #2
	b.ne	Lht_list
	ldr	q0, [x20]                 ; the key
	str	q0, [x19, #ST_KEY]
	mov	x0, x20
	bl	_free
	ldr	x0, [x19, #ST_KEYURL]
	bl	_free
	ldr	x0, [x19, #ST_RQURL]
	str	x0, [x19, #ST_KEYURL]
	str	xzr, [x19, #ST_RQURL]
	b	Lht_pump
Lht_list:
	mov	x0, x20
	CSTR	x1, "#EXT-X-STREAM-INF:"
	bl	_strstr
	cbz	x0, Lht_media
	ldr	x9, [x27, #E_MASTER]      ; a master playlist, once
	cbnz	x9, Lht_drop
	str	x20, [x27, #E_MASTER]
	ldr	x0, [x19, #ST_RQURL]
	str	x0, [x27, #E_MURL]
	str	xzr, [x19, #ST_RQURL]
	bl	hls_pick
	cbz	w0, Lht_end
	ldr	w9, [x27, #(E_ST + ST_SIZE + ST_KIND)]
	cbz	w9, Lht_pump              ; no sound rendition (a broadcast's DASH sound waits for Audio Only)
	BADDR	x0, (E_ST + ST_SIZE)
	bl	st_pump
	b	Lht_pump
Lht_media:
	ldr	x0, [x19, #ST_PL]
	bl	_free
	str	x20, [x19, #ST_PL]
	ldr	x9, [x19, #ST_SEQ]
	cbnz	x9, Lht_pump              ; already playing: it goes on from its sequence number
	mov	x0, x19                   ; the first: the whole playlist read, its length and end
	mov	w1, #1
	mov	x2, #0x7fffffffffffffff
	mov	x3, sp
	bl	seg_scan
	ldr	w9, [sp, #SG_TDUR]
	str	w9, [x19, #ST_TDUR]
	ldr	w9, [sp, #SG_END]
	str	w9, [x19, #ST_ENDED]
	cbnz	w9, 1f
	ldr	x10, [sp, #SG_SEQ0]       ; live: a few segments from its live edge, no length
	ldr	w11, [sp, #SG_N]
	subs	w11, w11, #HLS_LIVE_BACK
	csel	w11, w11, wzr, gt
	add	x10, x10, w11, uxtw
	str	x10, [x19, #ST_SEQ]
	b	Lht_pump
1:	ldr	x9, [x27, #E_DURMS]       ; on demand: its length, then the segment of the target
	cbnz	x9, 2f
	ldr	x9, [sp, #SG_T]
	str	x9, [x27, #E_DURMS]
2:	mov	x0, x19
	mov	w1, #1
	ldr	x2, [x19, #ST_PEND]       ; where it was sought
	mov	x3, sp
	bl	seg_scan
	ldr	x9, [sp, #SG_SEQ]
	str	x9, [x19, #ST_SEQ]
Lht_pump:
	mov	x0, x19
	bl	st_pump
	b	Lret2
Lht_drop:
	mov	x0, x20
	bl	_free
	b	Lht_pump
Lht_end:
	mov	x0, x19
	bl	st_end
	b	Lret2

; hls_done(stream, ok) — an HLS request ended: text read, a segment flushed (decrypted first) and timed for the bit rate, then the next.
hls_done:
	FRAME	3
	mov	x19, x0
	mov	w20, w1
	ldr	w9, [x19, #ST_REQT]
	cbz	w20, Lhd_fail
	str	wzr, [x19, #ST_ERRS]
	cmp	w9, #3
	b.eq	Lhd_seg
	b.hi	Lhd_map
	ldr	x0, [x19, #ST_TXT]        ; a playlist or key: NUL-terminated
	ldr	x1, [x19, #ST_TXTN]
	add	x1, x1, #1
	bl	_realloc
	cbz	x0, Lhd_fail
	ldr	x9, [x19, #ST_TXTN]
	strb	wzr, [x0, x9]
	str	x0, [x19, #ST_TXT]
	mov	x0, x19
	bl	hls_text
	b	Lret3
Lhd_map:
	ldr	x0, [x19, #ST_MAPURL]     ; the init segment read
	bl	_free
	ldr	x0, [x19, #ST_RQURL]
	str	x0, [x19, #ST_MAPURL]
	str	xzr, [x19, #ST_RQURL]
	b	Lhd_next
Lhd_seg:
	ldr	w9, [x19, #ST_ENC]
	cbz	w9, 1f
	mov	x0, x19                   ; AES-128: the whole segment, decrypted, then read
	bl	seg_decrypt
1:	mov	x0, x19
	bl	seg_flush
	ldr	x9, [x19, #ST_SEQ]
	add	x9, x9, #1
	str	x9, [x19, #ST_SEQ]
	BADDR	x10, E_ST
	cmp	x19, x10
	b.ne	Lhd_next                  ; the picture's stream times the network and picks the variant
	mov	w0, #CLOCK_UPTIME_RAW     ; its speed, averaged into the estimate
	bl	_clock_gettime_nsec_np
	ldr	x9, [x19, #ST_T1]
	sub	x9, x0, x9
	cmp	x9, #1
	csinc	x9, x9, xzr, hs
	ldr	x10, [x19, #ST_GOT]
	mov	x11, #0xca00              ; 8e9: bits, per second
	movk	x11, #0xdcd6, lsl #16
	movk	x11, #1, lsl #32
	mul	x10, x10, x11
	udiv	x10, x10, x9
	ldr	x11, [x27, #E_BPS]
	cbz	x11, 2f
	add	x11, x11, x11, lsl #1
	add	x10, x10, x11
	lsr	x10, x10, #2
2:	str	x10, [x27, #E_BPS]
	ldr	x9, [x27, #E_MASTER]
	cbz	x9, Lhd_next
	bl	hls_pick                  ; the picture's variant may change at the next segment
Lhd_next:
	mov	x0, x19
	bl	st_pump
	b	Lret3
Lhd_fail:
	ldr	w9, [x19, #ST_ERRS]
	add	w9, w9, #1
	str	w9, [x19, #ST_ERRS]
	cmp	w9, #NET_TRIES
	b.hs	1f
	mov	w0, #2000                 ; again in a second
	mov	x1, x19
	bl	st_later
	b	Lret3
1:	ldr	x9, [x19, #ST_SEQ]        ; that segment is lost: on to the next
	add	x9, x9, #1
	str	x9, [x19, #ST_SEQ]
	str	wzr, [x19, #ST_ERRS]
	ldr	w9, [x19, #ST_REQT]
	cmp	w9, #3
	b.eq	Lhd_next
	mov	x0, x19
	bl	st_end
	b	Lret3

; seg_decrypt(stream) — decrypt the collected segment in place (AES-128-CBC, PKCS7) and read it.
seg_decrypt:
	FRAME	1, 48
	mov	x19, x0
	ldp	x20, x9, [x19, #ST_TXT]   ; the segment and its length
	stp	xzr, xzr, [x19, #ST_TXT]
	cbz	x20, Lret1
	add	x10, sp, #32
	stp	x20, x9, [sp]             ; dataOut (in place), dataOutAvailable
	str	x10, [sp, #16]            ; dataOutMoved
	mov	w0, #1                    ; kCCDecrypt
	mov	w1, #0                    ; kCCAlgorithmAES128
	mov	w2, #1                    ; kCCOptionPKCS7Padding
	add	x3, x19, #ST_KEY
	mov	x4, #16
	add	x5, x19, #ST_IV
	mov	x6, x20
	mov	x7, x9
	bl	_CCCrypt
	cbnz	w0, 1f
	ldr	x2, [sp, #32]
	mov	x0, x19
	mov	x1, x20
	bl	seg_bytes
1:	mov	x0, x20
	bl	_free
	b	Lret1

; txt_add(stream, bytes, length) — append to the text being collected (a playlist, a key, an encrypted segment), at most BUF_MAX.
txt_add:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	ldp	x0, x22, [x19, #ST_TXT]
	add	x1, x22, x21
	mov	x9, #BUF_MAX
	cmp	x1, x9
	b.hi	Lret3                     ; too long: cut
	bl	_realloc
	cbz	x0, Lret3
	str	x0, [x19, #ST_TXT]
	add	x0, x0, x22
	mov	x1, x20
	mov	x2, x21
	bl	_memcpy
	add	x9, x22, x21
	str	x9, [x19, #ST_TXTN]
	b	Lret3

; vtt_cues(stream) — a WebVTT segment read: each cue's text, timed on the timeline by its X-TIMESTAMP-MAP, to the stream's subtitle track.
	.equ VC_BB,	8
	.equ VC_DUR,	16
	.equ VC_MEM,	24
vtt_cues:
	FRAME	4, 32
	mov	x20, x0
	ldr	x19, [x20, #ST_TR]
	ldp	x21, x22, [x20, #ST_TXT]
	stp	xzr, xzr, [x20, #ST_TXT]  ; the text is read here
	cbz	x21, Lret4
	mov	x0, x21
	add	x1, x22, #1
	bl	_realloc
	cbz	x0, Lvc_free
	mov	x21, x0
	strb	wzr, [x21, x22]
	cbz	x19, Lvc_free
	mov	x23, #0                   ; its cues' offset on the timeline, ms
	mov	x0, x21
	CSTR	x1, "MPEGTS:"
	bl	_strstr
	cbz	x0, 1f
	add	x0, x0, #7
	mov	x1, #0
	mov	w2, #10
	bl	_strtol
	mov	x9, #90
	sdiv	x23, x0, x9
1:	mov	x0, x21
	CSTR	x1, "LOCAL:"
	bl	_strstr
	cbz	x0, 2f
	add	x0, x0, #6
	bl	vtt_time
	sub	x23, x23, x0
2:	ldr	x9, [x27, #E_T0]
	cmp	x9, #0
	csel	x9, x9, xzr, gt
	mov	x10, #90
	sdiv	x9, x9, x10
	sub	x23, x23, x9
	mov	x24, x21
Lvc_cue:
	mov	x0, x24
	CSTR	x1, "-->"
	bl	_strstr
	cbz	x0, Lvc_free
	mov	x25, x0                   ; back to its line's start
3:	cmp	x0, x21
	b.ls	4f
	ldurb	w10, [x0, #-1]
	cmp	w10, #'\n'
	b.eq	4f
	sub	x0, x0, #1
	b	3b
4:	bl	vtt_time
	mov	x26, x0                   ; start
	add	x0, x25, #3
	bl	vtt_time
	sub	x9, x0, x26
	str	x9, [sp, #VC_DUR]
	mov	x0, x1                    ; the text: the next lines, to an empty one
	mov	w1, #'\n'
	bl	_strchr
	cbz	x0, Lvc_free
	add	x24, x0, #1
	mov	x25, x24
5:	ldrb	w10, [x25]
	cbz	w10, 7f
	cmp	w10, #'\n'
	b.ne	6f
	ldrb	w11, [x25, #1]
	cmp	w11, #'\r'
	cinc	x12, x25, eq
	ldrb	w11, [x12, #1]
	cmp	w11, #'\n'
	b.eq	7f
6:	add	x25, x25, #1
	b	5b
7:	mov	x9, x25
	cmp	x9, x24
	b.ls	8f
	ldurb	w10, [x9, #-1]
	cmp	w10, #'\r'
	cset	w10, eq
	sub	x9, x9, x10
8:	sub	x22, x9, x24              ; a tx3g sample: its length, then the text
	add	x0, x22, #2
	bl	_malloc
	cbz	x0, Lvc_free
	str	x0, [sp, #VC_MEM]
	rev16	w9, w22
	strh	w9, [x0], #2
	mov	x1, x24
	mov	x2, x22
	bl	_memcpy
	add	x9, sp, #VC_BB
	str	x9, [sp]                  ; the 9th argument
	mov	x0, #0
	ldr	x1, [sp, #VC_MEM]
	add	x2, x22, #2
	mov	x3, #0                    ; freed with it
	mov	x4, #0
	mov	x5, #0
	add	x6, x22, #2
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, Lvc_lost
	ldr	x0, [sp, #VC_BB]
	mov	x1, #0
	add	x2, x22, #2
	add	x4, x26, x23
	mov	x3, x4
	ldr	x5, [sp, #VC_DUR]
	mov	w6, #1
	bl	mk_sample
	mov	x22, x0
	ldr	x0, [sp, #VC_BB]
	bl	_CFRelease
	cbz	x22, Lvc_next
	mov	x0, x22
	bl	q_push
Lvc_next:
	mov	x24, x25
	b	Lvc_cue
Lvc_lost:
	ldr	x0, [sp, #VC_MEM]
	bl	_free
Lvc_free:
	mov	x0, x21
	bl	_free
	b	Lret4

; vtt_time(text) -> x0 = the WebVTT time there ([hh:]mm:ss.ttt) in ms, x1 = past it.
vtt_time:
	FRAME	2, 16
	mov	x20, x0
	mov	x19, #0
Lvt_part:
	mov	x0, x20
	mov	x1, sp
	mov	w2, #10
	bl	_strtol
	mov	x9, #60
	madd	x19, x19, x9, x0
	ldr	x20, [sp]
	ldrb	w9, [x20]
	cmp	w9, #':'
	cinc	x20, x20, eq
	b.eq	Lvt_part
	mov	x10, #1000
	mul	x19, x19, x10
	cmp	w9, #'.'
	b.ne	1f
	add	x0, x20, #1
	mov	x1, sp
	mov	w2, #10
	bl	_strtol
	add	x19, x19, x0
	ldr	x20, [sp]
1:	mov	x0, x19
	mov	x1, x20
	b	Lret2

; seg_bytes(stream, bytes, length) — a segment's bytes to its reader: TS, boxes (fMP4), packed audio or WebVTT, as its first byte tells.
seg_bytes:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	cbz	x21, Lret2
	ldr	w9, [x19, #ST_SEGF]
	cbnz	w9, 2f
	ldrb	w10, [x20]
	mov	w9, #1
	cmp	w10, #0x47                ; TS sync
	b.eq	1f
	mov	w9, #3
	mov	w11, #0xff
	cmp	w10, #'I'                 ; ID3: packed audio
	ccmp	w10, w11, #4, ne          ; ADTS or MPEG audio
	ccmp	w10, #0x0b, #4, ne        ; AC-3
	b.eq	1f
	mov	w9, #4
	cmp	w10, #'W'                 ; WEBVTT
	b.eq	1f
	mov	w9, #2                    ; boxes
1:	str	w9, [x19, #ST_SEGF]
	cmp	w9, #3
	b.ne	2f
	mov	x0, x19                   ; packed sound: no picture
	bl	no_pic
	ldr	w9, [x19, #ST_SEGF]
2:	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	cmp	w9, #2
	b.lo	3f
	b.eq	4f
	cmp	w9, #4
	b.eq	5f
	bl	pa_feed
	b	Lret2
3:	bl	ts_feed
	b	Lret2
4:	bl	st_parse
	b	Lret2
5:	bl	txt_add                   ; WebVTT: read whole at its end
	b	Lret2

; seg_flush(stream) — a TS segment's last PES of each kind is read now.
seg_flush:
	FRAME	1
	mov	x19, x0
	ldr	w9, [x19, #ST_SEGF]
	cmp	w9, #4
	b.ne	1f
	bl	vtt_cues
	b	Lret1
1:	cmp	w9, #1
	b.ne	Lret1
	mov	x0, x19
	mov	w1, #0
	bl	pes_done
	mov	x0, x19
	mov	w1, #1
	bl	pes_done
	mov	x0, x19
	bl	vau_flush
	b	Lret1

; ts_feed(stream, bytes, length) — TS packets, whole or split across calls.
ts_feed:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
Ltf_loop:
	cbz	x21, Lret3
	ldr	w9, [x19, #ST_TSN]
	cbnz	w9, Ltf_part
	cmp	x21, #188
	b.lo	Ltf_part
	ldrb	w10, [x20]
	cmp	w10, #0x47
	b.ne	Ltf_sync
	mov	x0, x19
	mov	x1, x20
	bl	ts_packet
	add	x20, x20, #188
	sub	x21, x21, #188
	b	Ltf_loop
Ltf_sync:
	add	x20, x20, #1              ; out of step: to the next sync byte
	sub	x21, x21, #1
	b	Ltf_loop
Ltf_part:
	mov	w10, #188
	sub	w22, w10, w9
	cmp	x22, x21
	csel	x22, x22, x21, lo
	add	x0, x19, #ST_TSC
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x22
	bl	_memcpy
	ldr	w9, [x19, #ST_TSN]
	add	w9, w9, w22
	str	w9, [x19, #ST_TSN]
	add	x20, x20, x22
	sub	x21, x21, x22
	cmp	w9, #188
	b.lo	Ltf_loop
	str	wzr, [x19, #ST_TSN]
	ldrb	w10, [x19, #ST_TSC]
	cmp	w10, #0x47
	b.ne	Ltf_loop
	mov	x0, x19
	add	x1, x19, #ST_TSC
	bl	ts_packet
	b	Ltf_loop

; ts_packet(stream, packet) — one 188-byte packet: the program tables, or a picture or sound PES.
ts_packet:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	ldrb	w9, [x20, #1]
	ldrb	w10, [x20, #2]
	and	w22, w9, #0x40            ; a unit starts here
	and	w9, w9, #0x1f
	orr	w21, w10, w9, lsl #8      ; PID
	ldrb	w9, [x20, #3]
	tbz	w9, #4, Lret2             ; no payload
	add	x1, x20, #4
	tbz	w9, #5, 1f
	ldrb	w10, [x20, #4]            ; past the adaptation field
	add	x1, x1, x10
	add	x1, x1, #1
1:	add	x9, x20, #188
	subs	x2, x9, x1
	b.ls	Lret2
	mov	x0, x19
	cbz	w21, Ltp_pat
	ldr	w9, [x19, #ST_PMT]
	cmp	w21, w9
	b.eq	Ltp_pmt
	mov	w4, w22
	ldr	w9, [x19, #ST_VPID]
	mov	w3, #0
	cmp	w21, w9
	b.eq	2f
	ldr	w9, [x19, #ST_APID]
	mov	w3, #1
	cmp	w21, w9
	b.ne	Lret2
2:	bl	pes_add
	b	Lret2
Ltp_pat:
	cbz	w22, Lret2
	bl	ts_pat
	b	Lret2
Ltp_pmt:
	cbz	w22, Lret2
	bl	ts_pmt
	b	Lret2

; ts_pat(stream, payload, length) — the program association table: the first program's map PID.
ts_pat:
	add	x13, x1, x2
	ldrb	w9, [x1]
	add	x1, x1, x9
	add	x1, x1, #1                ; the section, after the pointer field
	ldrb	w9, [x1, #1]
	ldrb	w10, [x1, #2]
	and	w9, w9, #0xf
	orr	w9, w10, w9, lsl #8
	add	x10, x1, #8
	add	x11, x1, x9
	sub	x11, x11, #1              ; less the CRC, after the 3-byte header
	cmp	x11, x13
	csel	x11, x11, x13, ls
1:	add	x12, x10, #4
	cmp	x12, x11
	b.hi	2f
	ldrh	w12, [x10]
	ldrh	w9, [x10, #2]
	add	x10, x10, #4
	cbz	w12, 1b                   ; the network PID
	rev16	w9, w9
	and	w9, w9, #0x1fff
	str	w9, [x0, #ST_PMT]
2:	ret

; ts_pmt(stream, payload, length) — the program map: the first picture (H.264, HEVC) and sound (AAC, MPEG audio, AC-3) PIDs, and their tracks.
ts_pmt:
	FRAME	3
	mov	x19, x0
	add	x20, x1, x2
	ldrb	w9, [x1]
	add	x1, x1, x9
	add	x1, x1, #1
	ldrb	w9, [x1, #1]
	ldrb	w10, [x1, #2]
	and	w9, w9, #0xf
	orr	w9, w10, w9, lsl #8
	add	x21, x1, x9
	sub	x21, x21, #1
	cmp	x21, x20
	csel	x21, x21, x20, ls
	ldrb	w9, [x1, #10]
	ldrb	w10, [x1, #11]
	and	w9, w9, #0xf
	orr	w9, w10, w9, lsl #8
	add	x22, x1, #12
	add	x22, x22, x9              ; the streams
Lpm_es:
	add	x9, x22, #5
	cmp	x9, x21
	b.hi	Lpm_end
	ldrb	w9, [x22]                 ; stream type
	ldrb	w10, [x22, #1]
	ldrb	w11, [x22, #2]
	and	w10, w10, #0x1f
	orr	w23, w11, w10, lsl #8     ; PID
	ldrb	w11, [x22, #3]
	ldrb	w12, [x22, #4]
	and	w11, w11, #0xf
	orr	w11, w12, w11, lsl #8
	add	x22, x22, #5
	add	x22, x22, x11
	mov	w24, #0
	cmp	w9, #0x1b                 ; H.264
	b.eq	Lpm_pic
	mov	w24, #1
	cmp	w9, #0x24                 ; HEVC
	b.eq	Lpm_pic
	TYPE	w24, 'a','d','t','s'      ; AudioFileStream's hint
	cmp	w9, #0x0f
	b.eq	Lpm_snd
	TYPE	w24, 'M','P','G','3'
	cmp	w9, #0x03
	ccmp	w9, #0x04, #4, ne
	b.eq	Lpm_snd
	TYPE	w24, 'a','c','-','3'
	cmp	w9, #0x81
	b.ne	Lpm_es
Lpm_snd:
	ldr	w9, [x19, #ST_APID]
	cbnz	w9, Lpm_es
	str	w23, [x19, #ST_APID]
	ldr	x9, [x19, #ST_AT]
	cbnz	x9, Lpm_es
	mov	x0, x19
	mov	w1, #'a'
	mov	w2, #(90000 & 0xffff)
	movk	w2, #(90000 >> 16), lsl #16
	bl	trk_new
	cbz	x0, Lpm_es
	str	x0, [x19, #ST_AT]
	rev	w1, w24                   ; the hint, as a four-character code
	bl	afs_open
	b	Lpm_es
Lpm_pic:
	ldr	w9, [x19, #ST_VPID]
	cbnz	w9, Lpm_es
	str	w23, [x19, #ST_VPID]
	str	w24, [x19, #ST_VHEVC]
	ldr	x9, [x19, #ST_VT]
	cbnz	x9, Lpm_es
	mov	x0, x19
	mov	w1, #'v'
	mov	w2, #(90000 & 0xffff)
	movk	w2, #(90000 >> 16), lsl #16
	bl	trk_new
	str	x0, [x19, #ST_VT]
	b	Lpm_es
Lpm_end:
	mov	x0, x19
	bl	no_pic
	b	Lret3

; pes_add(stream, data, length, sound, start) — gather a PES: the previous one is read when the next starts.
pes_add:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	mov	w22, w3
	add	x23, x19, #ST_VPES
	cbz	w22, 1f
	add	x23, x19, #ST_APES
1:	ldr	x9, [x23, #8]
	cbz	w4, 2f
	cbz	x9, 3f
	mov	x0, x19
	mov	w1, w22
	bl	pes_done
	b	3f
2:	cbz	x9, Lret3                 ; the middle of a PES whose start was missed
3:	mov	x0, x23
	mov	x1, x20
	mov	x2, x21
	bl	buf_add
	b	Lret3

; buf_add(buffer, bytes, length) — append to a {data, length, room} buffer, room grown to twice what it needs (at least 64 KiB); all dropped without memory.
buf_add:
	FRAME	3
	mov	x23, x0
	mov	x20, x1
	mov	x21, x2
	ldp	x0, x9, [x23]
	ldr	x10, [x23, #16]
	add	x24, x9, x21
	cmp	x24, x10
	b.ls	4f
	lsl	x1, x24, #1
	mov	x11, #0x10000
	cmp	x1, x11
	csel	x1, x1, x11, hs
	str	x1, [x23, #16]
	bl	_realloc
	cbz	x0, Lba_lost
	str	x0, [x23]
4:	ldp	x0, x9, [x23]
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x21
	bl	_memcpy
	ldr	x9, [x23, #8]
	add	x9, x9, x21
	str	x9, [x23, #8]
	b	Lret3
Lba_lost:
	ldr	x0, [x23]
	bl	_free
	stp	xzr, xzr, [x23]
	str	xzr, [x23, #16]
	b	Lret3

; pes_done(stream, sound) — read a gathered PES: its times, anchored on the HLS timeline, then its picture or sound.
pes_done:
	FRAME	4
	mov	x19, x0
	mov	w22, w1
	add	x23, x19, #ST_VPES
	cbz	w22, 1f
	add	x23, x19, #ST_APES
1:	ldp	x20, x21, [x23]
	str	xzr, [x23, #8]
	cmp	x21, #14
	b.lo	Lret4
	ldr	w9, [x20]
	and	w9, w9, #0xffffff
	cmp	w9, #0x10000              ; 00 00 01
	b.ne	Lret4
	ldrb	w9, [x20, #7]             ; PTS, DTS flags
	ldrb	w10, [x20, #8]
	add	x24, x10, #9              ; the payload
	cmp	x24, x21
	b.hs	Lret4
	mov	x25, #-1                  ; untimed: a picture's goes on the waiting unit
	tbz	w9, #7, Lpz_cont
	add	x0, x20, #9
	bl	pts33
	mov	x25, x0
	mov	x26, x0
	tbz	w9, #6, 2f
	add	x0, x20, #14
	bl	pts33
	mov	x26, x0
2:	ldr	x9, [x27, #E_T0]          ; the timeline: the first PTS less its segment's start
	tbz	x9, #63, 3f
	ldr	x10, [x19, #ST_SEGT]
	mov	x11, #90
	msub	x9, x10, x11, x25
	str	x9, [x27, #E_T0]
3:	sub	x25, x25, x9
	sub	x26, x26, x9
	ldr	x0, [x19, #ST_VT]
	cbz	w22, 4f
	ldr	x0, [x19, #ST_AT]
4:	cbz	x0, Lret4
	add	x1, x20, x24
	sub	x2, x21, x24
	mov	x3, x25
	mov	x4, x26
	cbnz	w22, 5f
	bl	vau_next
	b	Lret4
Lpz_cont:
	cbnz	w22, Lret4
	ldr	x0, [x19, #ST_VT]
	cbz	x0, Lret4
	add	x1, x20, x24
	sub	x2, x21, x24
	mov	x3, x25
	bl	vau_next
	b	Lret4
5:	bl	afs_feed
	b	Lret4

; pts33(p) -> x0 = a PES time stamp's 33 bits (x0 in; w9 kept).
pts33:
	ldrb	w10, [x0]
	ubfx	w10, w10, #1, #3
	ldrh	w11, [x0, #1]
	rev16	w11, w11
	lsr	w11, w11, #1
	ldrh	w12, [x0, #3]
	rev16	w12, w12
	lsr	w12, w12, #1
	lsl	x10, x10, #30
	orr	x10, x10, x11, lsl #15
	orr	x0, x10, x12
	ret

; next_sc(p, end) -> x0 = the next 00 00 01 at or after p, or end: 16 bytes at a time while none of them is zero.
next_sc:
1:	add	x9, x0, #16
	cmp	x9, x1
	b.hi	3f
	ldr	q0, [x0]
	cmeq	v0.16b, v0.16b, #0
	umaxv	b0, v0.16b
	fmov	w9, s0
	cbnz	w9, 2f
	add	x0, x0, #16
	b	1b
2:	add	x10, x0, #16              ; a zero in these 16: byte by byte
	b	4f
3:	mov	x10, x1
4:	add	x9, x0, #3
	cmp	x9, x1
	b.hi	6f
	ldrb	w9, [x0]
	cbnz	w9, 5f
	ldrb	w9, [x0, #1]
	cbnz	w9, 5f
	ldrb	w9, [x0, #2]
	cmp	w9, #1
	b.eq	7f
5:	add	x0, x0, #1
	cmp	x0, x10
	b.lo	4b
	b	1b
6:	mov	x0, x1
7:	ret

; ts_video(track, data, length, pts, dts, duration) — an access unit in Annex B: length-prefixed NAL units for the decoder, parameter sets kept for its format, a sync flag for IDR/IRAP pictures.
	.equ TV_NEXT,	8
	.equ TV_KEY,	16
	.equ TV_BB,	24
	.equ TV_LEN,	32
	.equ TV_DUR,	40
ts_video:
	FRAME	4, 48
	mov	x19, x0
	mov	x20, x1
	add	x21, x1, x2
	mov	x22, x3
	mov	x23, x4
	str	x5, [sp, #TV_DUR]
	ldr	x24, [x19, #TR_ST]
	add	x0, x2, x2, lsr #1        ; start codes become 4-byte lengths
	add	x0, x0, #16
	bl	_malloc
	cbz	x0, Lret4
	mov	x25, x0
	mov	x26, x0
	str	xzr, [sp, #TV_KEY]
	mov	x0, x20
	mov	x1, x21
	bl	next_sc
	mov	x20, x0
Ltv_nal:
	cmp	x20, x21
	b.hs	Ltv_done
	add	x20, x20, #3
	mov	x0, x20
	mov	x1, x21
	bl	next_sc
	str	x0, [sp, #TV_NEXT]
1:	cmp	x0, x20                   ; its trailing zeros belong to the next start code
	b.ls	2f
	ldurb	w9, [x0, #-1]
	cbnz	w9, 2f
	sub	x0, x0, #1
	b	1b
2:	subs	x2, x0, x20
	b.eq	Ltv_skip
	ldrb	w10, [x20]
	ldr	w11, [x24, #ST_VHEVC]
	cbnz	w11, Ltv_hevc
	and	w10, w10, #0x1f
	cmp	w10, #7
	b.eq	Ltv_sps
	cmp	w10, #8
	b.eq	Ltv_pps
	cmp	w10, #9
	b.eq	Ltv_skip                  ; access unit delimiter
	cmp	w10, #5
	b.ne	Ltv_copy
	b	Ltv_iframe

Ltv_hevc:
	ubfx	w10, w10, #1, #6
	cmp	w10, #32
	b.eq	Ltv_vps
	cmp	w10, #33
	b.eq	Ltv_sps
	cmp	w10, #34
	b.eq	Ltv_pps
	cmp	w10, #35
	b.eq	Ltv_skip
	sub	w12, w10, #16
	cmp	w12, #8
	b.hs	Ltv_copy
Ltv_iframe:
	mov	w12, #1
	str	w12, [sp, #TV_KEY]
Ltv_copy:
	rev	w12, w2
	str	w12, [x26], #4
	mov	x0, x26
	mov	x1, x20
	add	x26, x26, x2
	bl	_memcpy
Ltv_skip:
	ldr	x20, [sp, #TV_NEXT]
	b	Ltv_nal
Ltv_vps:
	mov	w1, #0
	b	Ltv_ps
Ltv_sps:
	mov	w1, #1
	b	Ltv_ps
Ltv_pps:
	mov	w1, #2
Ltv_ps:
	mov	x3, x2
	mov	x2, x20
	mov	x0, x24
	bl	ps_store
	b	Ltv_skip
Ltv_done:
	sub	x9, x26, x25              ; the length-prefixed unit
	cbz	x9, Ltv_free
	str	x9, [sp, #TV_LEN]
	ldr	w9, [x24, #ST_PSNEW]
	cbz	w9, 3f
	str	wzr, [x24, #ST_PSNEW]
	mov	x0, x19
	bl	ps_format
3:	ldr	x9, [x19, #TR_FD]
	cbz	x9, Ltv_free              ; no parameter sets yet
	add	x9, sp, #TV_BB
	str	x9, [sp]
	mov	x0, #0
	mov	x1, x25
	ldr	x2, [sp, #TV_LEN]
	mov	x3, #0                    ; the default allocator frees it with the sample
	mov	x4, #0
	mov	x5, #0
	mov	x6, x2
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, Ltv_free
	ldr	x0, [sp, #TV_BB]
	mov	x1, #0
	ldr	x2, [sp, #TV_LEN]
	mov	x3, x23
	mov	x4, x22
	ldr	x5, [sp, #TV_DUR]
	ldr	w6, [sp, #TV_KEY]
	bl	mk_sample
	mov	x20, x0
	ldr	x0, [sp, #TV_BB]
	bl	_CFRelease
	cbz	x20, Lret4
	mov	x0, x20
	bl	q_push
	b	Lret4
Ltv_free:
	mov	x0, x25
	bl	_free
	b	Lret4

; ---- CEA-608 captions (CC1, field 1), from H.264 SEI in presentation order, as cues of the caption track ----

; cc_avcc(bb, offset, size, pts) — a picture's NAL units (4-byte lengths): each H.264 or HEVC SEI to cc_sei.
cc_avcc:
	FRAME	3, 16
	mov	x21, x2
	mov	x22, x3
	stp	xzr, xzr, [sp]
	mov	x2, sp
	mov	x3, #0
	add	x4, sp, #8
	bl	_CMBlockBufferGetDataPointer
	ldp	x9, x19, [sp]             ; contiguous bytes there, the pointer
	cmp	x9, x21
	b.lo	Lret3
	add	x20, x19, x21
1:	add	x9, x19, #5
	cmp	x9, x20
	b.hi	Lret3
	ldr	w9, [x19], #4
	rev	w9, w9
	add	x23, x19, x9              ; the next unit
	cmp	x23, x20
	b.hi	Lret3
	ldrb	w10, [x19]
	and	w11, w10, #0x1f
	cmp	w11, #6                   ; H.264 SEI: its messages after one header byte
	mov	x0, x19
	b.eq	2f
	ubfx	w11, w10, #1, #6
	cmp	w11, #39                  ; HEVC prefix SEI: after two
	b.ne	3f
	add	x0, x19, #1
2:	mov	x1, x23
	mov	x2, x22
	bl	cc_sei
3:	mov	x19, x23
	b	1b

; cc_sei(nal, end, pts) — an SEI's caption data (ATSC A/53 "GA94"), waiting for presentation order.
cc_sei:
	FRAME	2, 32
	add	x19, x0, #1
	mov	x20, x1
	mov	x21, x2
Lcs_msg:
	mov	w9, #0                    ; payload type and size: 0xff bytes add up
1:	cmp	x19, x20
	b.hs	Lret2
	ldrb	w10, [x19], #1
	add	w9, w9, w10
	cmp	w10, #0xff
	b.eq	1b
	mov	w11, #0
2:	cmp	x19, x20
	b.hs	Lret2
	ldrb	w10, [x19], #1
	add	w11, w11, w10
	cmp	w10, #0xff
	b.eq	2b
	add	x22, x19, x11             ; the next message
	cmp	x22, x20
	b.hi	Lret2
	cmp	w9, #4                    ; registered user data: B5 0031 "GA94" 03, then cc_data
	ccmp	w11, #10, #0, eq
	b.lo	3f
	ldr	x9, [x19]
	mov	x10, #0x00b5
	movk	x10, #0x4731, lsl #16
	movk	x10, #0x3941, lsl #32
	movk	x10, #0x0334, lsl #48
	cmp	x9, x10
	b.ne	3f
	ldrb	w9, [x19, #8]
	and	w9, w9, #31               ; cc_count
	add	x10, x19, #10
	mov	w12, #0
	add	x13, sp, #8
4:	cbz	w9, 5f
	add	x14, x10, #3
	cmp	x14, x22
	b.hi	5f
	ldrb	w14, [x10]
	and	w15, w14, #7
	cmp	w15, #4                   ; valid, field 1
	b.ne	6f
	cmp	w12, #8
	b.hs	6f
	ldrh	w15, [x10, #1]
	strh	w15, [x13, x12, lsl #1]
	add	w12, w12, #1
6:	add	x10, x10, #3
	sub	w9, w9, #1
	b	4b
5:	mov	x0, x21
	add	x1, sp, #8
	mov	w2, w12
	bl	cc_add
3:	mov	x19, x22
	b	Lcs_msg

; cc_add(pts, pairs, count) — into the waiting captions, by time; past four, the earliest is decoded.
cc_add:
	FRAME	3
	BADDR	x19, E_CC
	ldr	w9, [x19, #CC_QN]
	add	x10, x19, #CC_Q
	mov	w11, w9                   ; its place: after the earlier ones
1:	cbz	w11, 2f
	sub	w12, w11, #1
	add	x13, x10, x12, lsl #5
	ldr	x14, [x13]
	cmp	x14, x0
	b.le	2f
	ldp	q0, q1, [x13]             ; a later one moves up
	stp	q0, q1, [x13, #CC_E]
	mov	w11, w12
	b	1b
2:	add	x13, x10, x11, lsl #5
	str	x0, [x13]
	str	w2, [x13, #8]
	ldr	q0, [x1]
	str	q0, [x13, #16]
	add	w9, w9, #1
	str	w9, [x19, #CC_QN]
	cmp	w9, #5
	b.lo	Lret3
	mov	x20, x10                  ; the earliest, decoded
	ldr	w21, [x20, #8]
	add	x22, x20, #16
	mov	w23, #0
3:	cbz	w21, 4f
	ldrb	w0, [x22], #1
	ldrb	w1, [x22], #1
	bl	cc_pair
	orr	w23, w23, w0
	sub	w21, w21, #1
	b	3b
4:	cbz	w23, 5f
	ldr	x0, [x20]
	bl	cc_cue
5:	ldr	w9, [x19, #CC_QN]
	sub	w9, w9, #1
	str	w9, [x19, #CC_QN]
	add	x10, x19, #CC_Q
6:	cbz	w9, Lret3
	ldp	q0, q1, [x10, #CC_E]
	stp	q0, q1, [x10], #CC_E
	sub	w9, w9, #1
	b	6b

; cc_pair(b1, b2) -> w0 = 1 when the shown caption changed: a CEA-608 byte pair of CC1 (x19 = E_CC).
cc_pair:
	FRAME	2
	and	w0, w0, #0x7f
	and	w1, w1, #0x7f
	add	x20, x19, #CC_N           ; the target: loading (pop-on), or shown
	ldr	w9, [x19, #CC_MODE]
	cmp	w9, #0
	add	x9, x19, #CC_D
	csel	x20, x20, x9, eq
	cbz	w0, Lcp_no
	sub	w9, w0, #0x10
	cmp	w9, #0x10
	b.hs	Lcp_text
	orr	w9, w1, w0, lsl #8        ; a control code: the copy that follows it is dropped
	ldr	w10, [x19, #CC_LAST]
	cmp	w9, w10
	csel	w11, wzr, w9, eq
	str	w11, [x19, #CC_LAST]
	b.eq	Lcp_no
	ubfx	w10, w0, #3, #1
	str	w10, [x19, #CC_CHAN]
	cbnz	w10, Lcp_no               ; CC2's
	bic	w0, w0, #8                ; as for CC1
	cmp	w1, #0x40
	b.hs	Lcp_row                   ; a preamble: a row of its own
	cmp	w0, #0x14
	b.ne	Lcp_no                    ; styles, special and extended characters, tabs
	cmp	w1, #0x20                 ; RCL: pop-on
	b.ne	1f
	str	wzr, [x19, #CC_MODE]
	b	Lcp_no
1:	sub	w9, w1, #0x25             ; RU2-RU4: roll-up
	cmp	w9, #3
	b.hs	2f
	add	w9, w9, #2
	mov	w10, #1
	stp	w10, w9, [x19, #CC_MODE]
	b	Lcp_no
2:	cmp	w1, #0x29                 ; RDC: paint-on
	b.ne	3f
	mov	w9, #2
	str	w9, [x19, #CC_MODE]
	b	Lcp_no
3:	cmp	w1, #0x2c                 ; EDM: the shown one erased
	b.ne	4f
	str	wzr, [x19, #CC_D]
	b	Lcp_yes
4:	cmp	w1, #0x2e                 ; ENM: the loading one
	b.ne	5f
	str	wzr, [x19, #CC_N]
	b	Lcp_no
5:	cmp	w1, #0x2f                 ; EOC: the loaded one shown, the shown one loading
	b.ne	6f
	add	x9, x19, #CC_D
	mov	w10, #4
7:	ldp	q0, q1, [x9]
	ldp	q2, q3, [x9, #128]
	stp	q2, q3, [x9]
	stp	q0, q1, [x9, #128]
	add	x9, x9, #32
	subs	w10, w10, #1
	b.ne	7b
	b	Lcp_yes
6:	cmp	w1, #0x2d                 ; CR: roll-up's rows move up
	b.ne	8f
	ldr	w9, [x19, #CC_MODE]
	cmp	w9, #1
	b.ne	Lcp_no
	add	x20, x19, #CC_D
	mov	w0, #'\n'
	bl	cc_put
	add	x9, x20, #4               ; its last rows stay: the oldest lines go
	ldr	w10, [x20]
	add	x13, x9, x10
	mov	x12, x9
	mov	w14, #1
9:	cmp	x12, x13
	b.hs	10f
	ldrb	w15, [x12], #1
	cmp	w15, #'\n'
	cinc	w14, w14, eq
	b	9b
10:	ldr	w11, [x19, #CC_ROWS]
	subs	w14, w14, w11
	b.le	Lcp_yes
	mov	x12, x9
11:	ldrb	w15, [x12], #1
	cmp	w15, #'\n'
	b.ne	11b
	subs	w14, w14, #1
	b.ne	11b
	sub	x2, x13, x12
	str	w2, [x20]
	mov	x0, x9
	mov	x1, x12
	bl	_memmove
	b	Lcp_yes
8:	cmp	w1, #0x21                 ; BS
	b.ne	Lcp_no
	ldr	w9, [x20]
	cbz	w9, Lcp_no
	sub	w9, w9, #1
	str	w9, [x20]
	b	Lcp_target
Lcp_row:
	ldr	w9, [x20]
	cbz	w9, Lcp_no
	add	x10, x20, #3
	ldrb	w10, [x10, x9]
	cmp	w10, #'\n'
	b.eq	Lcp_no
	mov	w0, #'\n'
	bl	cc_put
	b	Lcp_target
Lcp_text:
	ldr	w9, [x19, #CC_CHAN]
	cbnz	w9, Lcp_no
	mov	w21, w1
	bl	cc_put
	cmp	w21, #0x20
	b.lo	Lcp_target
	mov	w0, w21
	bl	cc_put
Lcp_target:
	add	x9, x19, #CC_D
	cmp	x20, x9
	cset	w0, eq
	b	Lret2
Lcp_yes:
	mov	w0, #1
	b	Lret2
Lcp_no:
	mov	w0, #0
	b	Lret2

; cc_put(char) — a CEA-608 character onto the target caption, as UTF-8 (x20 = it).
cc_put:
	ldr	w9, [x20]
	cmp	w9, #120
	b.hs	3f                        ; full
	add	x10, x20, #4
	adr	x11, Lcc_latin
1:	ldrb	w12, [x11], #3
	cbz	w12, 2f
	cmp	w12, w0
	b.ne	1b
	ldurh	w12, [x11, #-2]           ; a letter of its own: two UTF-8 bytes
	strh	w12, [x10, x9]
	add	w9, w9, #2
	str	w9, [x20]
	ret
2:	strb	w0, [x10, x9]
	add	w9, w9, #1
	str	w9, [x20]
3:	ret
Lcc_latin:	                          ; its code, then the UTF-8 it stands for
	.byte	0x2a, 0xc3, 0xa1, 0x5c, 0xc3, 0xa9, 0x5e, 0xc3, 0xad, 0x5f, 0xc3, 0xb3, 0x60, 0xc3, 0xba
	.byte	0x7b, 0xc3, 0xa7, 0x7c, 0xc3, 0xb7, 0x7d, 0xc3, 0x91, 0x7e, 0xc3, 0xb1, 0
	.p2align 2

; cc_cue(pts) — the shown caption from that moment, a tx3g cue of the caption track (until the next).
cc_cue:
	FRAME	3, 32
	mov	x20, x0
	BADDR	x21, (E_CC + CC_D)
	ldr	w22, [x21]
	add	x0, x22, #2
	bl	_malloc
	cbz	x0, Lret3
	mov	x23, x0
	rev16	w9, w22
	strh	w9, [x0], #2
	add	x1, x21, #4
	mov	x2, x22
	bl	_memcpy
	add	x9, sp, #8
	str	x9, [sp]
	mov	x0, #0
	mov	x1, x23
	add	x2, x22, #2
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	add	x6, x22, #2
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, 1f
	ldr	x19, [x27, #E_CCT]
	ldr	x0, [sp, #8]
	mov	x1, #0
	add	x2, x22, #2
	mov	x3, x20
	mov	x4, x20
	mov	x5, #(16 * 90000 & 0xffff)  ; 16 s at most
	movk	x5, #(16 * 90000 >> 16), lsl #16
	mov	w6, #1
	bl	mk_sample
	mov	x22, x0
	ldr	x0, [sp, #8]
	bl	_CFRelease
	cbz	x22, Lret3
	mov	x0, x22
	bl	q_push
	b	Lret3
1:	mov	x0, x23
	bl	_free
	b	Lret3

; vau_next(track, bytes, length, pts, dts) — a picture PES: what comes before its first start code ends the waiting access unit, which goes on; the rest waits (pts -1: all of it ends the waiting one).
vau_next:
	FRAME	4
	mov	x19, x0
	mov	x20, x1
	add	x21, x1, x2
	mov	x22, x3
	mov	x23, x4
	ldr	x24, [x19, #TR_ST]
	add	x24, x24, #ST_VPEN
	mov	x25, x21
	tbnz	x22, #63, 1f
	mov	x0, x20
	mov	x1, x21
	bl	next_sc
	mov	x25, x0
1:	ldr	x9, [x24, #8]
	cbz	x9, 2f                    ; nothing waits: no unit to end
	mov	x0, x24
	mov	x1, x20
	sub	x2, x25, x20
	bl	buf_add
2:	tbnz	x22, #63, Lret4
	ldr	x2, [x24, #8]
	cbz	x2, 3f
	mov	x0, x19                   ; the waiting unit, whole now: it lasts until this one's decode time
	ldr	x1, [x24]
	ldp	x3, x4, [x24, #24]
	sub	x5, x23, x4
	str	x5, [x24, #16 + 24]       ; ST_VPEN's duration slot
	bl	ts_video
3:	str	xzr, [x24, #8]
	stp	x22, x23, [x24, #24]
	mov	x0, x24
	mov	x1, x25
	sub	x2, x21, x25
	bl	buf_add
	b	Lret4

; vau_flush(stream) — the access unit waiting goes on: its segment ended.
vau_flush:
	FRAME	1
	add	x19, x0, #ST_VPEN
	ldr	x2, [x19, #8]
	ldr	x0, [x0, #ST_VT]
	cbz	x2, Lret1
	str	xzr, [x19, #8]
	cbz	x0, Lret1
	ldr	x1, [x19]
	ldp	x3, x4, [x19, #24]
	ldr	x5, [x19, #40]            ; as long as the one before
	bl	ts_video
	b	Lret1

; ps_store(stream, slot, nal, length) — keep a parameter set (VPS 0, SPS 1, PPS 2); a changed one asks for a new format.
ps_store:
	FRAME	3
	cmp	x3, #252
	b.hi	Lret3
	mov	x19, x0
	add	x20, x0, #ST_PS
	add	x20, x20, x1, lsl #8
	mov	x21, x2
	mov	x22, x3
	ldr	w9, [x20]
	cmp	w9, w22
	b.ne	1f
	add	x0, x20, #4
	mov	x1, x21
	mov	x2, x22
	bl	_memcmp
	cbz	w0, Lret3                 ; the same
1:	str	w22, [x20]
	add	x0, x20, #4
	mov	x1, x21
	mov	x2, x22
	bl	_memcpy
	mov	w9, #1
	str	w9, [x19, #ST_PSNEW]
	b	Lret3

; ps_format(track) — the picture's format from its stream's parameter sets.
ps_format:
	FRAME	1, 64
	mov	x19, x0
	ldr	x20, [x19, #TR_ST]
	add	x9, x20, #ST_PS
	ldr	w10, [x9]
	ldr	w11, [x9, #256]
	ldr	w12, [x9, #512]
	add	x13, x9, #4
	add	x14, x9, #260
	add	x15, x9, #516
	stp	x13, x14, [sp]            ; pointers: VPS, SPS, PPS
	str	x15, [sp, #16]
	stp	x10, x11, [sp, #24]       ; and sizes
	str	x12, [sp, #40]
	cbz	w11, Lret1
	cbz	w12, Lret1
	ldr	w9, [x20, #ST_VHEVC]
	cbnz	w9, 1f
	mov	x0, #0                    ; H.264: SPS, PPS
	mov	x1, #2
	add	x2, sp, #8
	add	x3, sp, #32
	mov	w4, #4
	add	x5, sp, #48
	bl	_CMVideoFormatDescriptionCreateFromH264ParameterSets
	b	2f
1:	cbz	w10, Lret1
	mov	x0, #0                    ; HEVC: VPS, SPS, PPS
	mov	x1, #3
	mov	x2, sp
	add	x3, sp, #24
	mov	w4, #4
	mov	x5, #0
	add	x6, sp, #48
	bl	_CMVideoFormatDescriptionCreateFromHEVCParameterSets
2:	cbnz	w0, Lret1
	ldr	x0, [x19, #TR_FD]
	cbz	x0, 3f
	bl	_CFRelease
3:	ldr	x0, [sp, #48]
	str	x0, [x19, #TR_FD]
	bl	vid_dims
	b	Lret1

; vid_dims — the picture's shown size, its pixel aspect and clean aperture applied (x19 = track).
vid_dims:
	FRAME	0
	ldr	x0, [x19, #TR_FD]
	mov	w1, #1
	mov	w2, #1
	bl	_CMVideoFormatDescriptionGetPresentationDimensions
	fcvtzu	w9, d0
	fcvtzu	w10, d1
	str	w9, [x19, #TR_DW]
	str	w10, [x19, #TR_DH]
	b	Lret0

; afs_file -> w0 = 1 when the mapped file is sound AudioFileStream reads (MP3, ADTS, FLAC, WAV, AIFF, CAF, AC-3): its packets fill a track's queue as it drains.
afs_file:
	FRAME	1
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Laf_no
	add	w10, w9, #1
	str	w10, [x27, #E_NTR]
	BADDR	x19, E_TR
	add	x19, x19, x9, lsl #9
	mov	w9, #'a'
	mov	w10, #(90000 & 0xffff)
	movk	w10, #(90000 >> 16), lsl #16
	stp	w9, w10, [x19, #TR_KIND]
	mov	w9, #1
	str	w9, [x19, #TR_SRC]
	mov	x0, #(FIFO_N * 8)
	bl	_malloc
	str	x0, [x19, #TR_FQ]
	cbz	x0, Laf_no
	mov	x0, x19
	mov	w1, #0                    ; its type sniffed
	bl	afs_open
	cbnz	w0, Laf_no
1:	bl	afs_more                  ; read until it knows the format: within the first MiB
	ldr	x9, [x19, #TR_FD]
	cbnz	x9, 2f
	cbz	w0, Laf_no
	ldr	x9, [x19, #TR_OFF]
	cmp	x9, #0x100000
	b.lo	1b
	b	Laf_no
2:	str	x19, [x27, #E_AT]
	bl	afs_dur
	mov	w0, #1
	b	Lret1
Laf_no:
	mov	w0, #0
	b	Lret1

; afs_more -> w0 = 1 while the mapped file goes on: its next 64 KiB to the track's AudioFileStream, 0 at the end or for what it cannot read (x19 = track).
afs_more:
	FRAME	0
	ldr	x9, [x19, #TR_OFF]
	ldr	x10, [x27, #E_LEN]
	subs	x1, x10, x9
	b.ls	1f
	mov	x11, #0x10000
	cmp	x1, x11
	csel	x1, x1, x11, ls
	add	x10, x9, x1
	str	x10, [x19, #TR_OFF]
	ldr	x0, [x19, #TR_AFS]
	ldr	x2, [x27, #E_MAP]
	add	x2, x2, x9
	ldr	w3, [x19, #TR_AFLAG]
	str	wzr, [x19, #TR_AFLAG]
	bl	_AudioFileStreamParseBytes
	cmp	w0, #0
	cset	w0, eq
	b	Lret0
1:	mov	w0, #0
	b	Lret0

; afs_get(property, out) -> w0 = 0 when the track's AudioFileStream gave it (out: up to 8 bytes, zeroed first) (x19 = track).
afs_get:
	FRAME	0, 16
	str	xzr, [x1]
	mov	x3, x1
	mov	w1, w0
	mov	w9, #8
	str	w9, [sp]
	mov	x2, sp
	ldr	x0, [x19, #TR_AFS]
	bl	_AudioFileStreamGetProperty
	b	Lret0

; afs_dur — a sound file's length: its packets', else its data's at its bit rate (x19 = track).
afs_dur:
	FRAME	1, 16
	mov	w0, #(AFS_DOFF & 0xffff)
	movk	w0, #(AFS_DOFF >> 16), lsl #16
	mov	x1, sp
	bl	afs_get
	ldr	x20, [sp]                 ; the data's start
	mov	w0, #(AFS_PCNT & 0xffff)
	movk	w0, #(AFS_PCNT >> 16), lsl #16
	add	x1, sp, #8
	bl	afs_get
	ldr	x9, [sp, #8]
	ldr	w10, [x19, #TR_ASR]
	ldr	w11, [x19, #TR_AFPP]
	mov	x12, #1000
	cbz	x9, 1f
	cbz	w10, 1f
	mul	x9, x9, x11               ; packets x frames x 1000 / rate
	mul	x9, x9, x12
	udiv	x9, x9, x10
	b	2f
1:	mov	w0, #(AFS_BRAT & 0xffff)
	movk	w0, #(AFS_BRAT >> 16), lsl #16
	add	x1, sp, #8
	bl	afs_get
	ldr	x9, [x27, #E_LEN]
	ldr	x10, [x19, #TR_ST]
	cbz	x10, 4f
	ldr	x9, [x10, #ST_LEN]
4:	subs	x9, x9, x20               ; its data
	b.ls	Lret1
	ldr	w10, [sp, #8]
	cbz	w10, 3f
	mov	x12, #8000                ; bytes x 8000 / bits per second
	mul	x9, x9, x12
	udiv	x9, x9, x10
	b	2f
3:	ldr	x10, [x19, #TR_OFF]       ; no rate either: as long as the part read lasts, scaled to the whole
	subs	x10, x10, x20
	b.ls	Lret1
	ldr	x11, [x19, #TR_APTS]
	mul	x9, x9, x11
	udiv	x9, x9, x10
	mov	x10, #90
	udiv	x9, x9, x10
2:	str	x9, [x27, #E_DURMS]
	b	Lret1

; afs_seek(ms) — a sound file from the packet at that moment: AudioFileStreamSeek's byte past its data's start, read as a discontinuity (x19 = track).
afs_seek:
	FRAME	1, 32
	mov	x20, x0
	bl	q_clear
	ldr	w9, [x19, #TR_ASR]
	ldr	w10, [x19, #TR_AFPP]
	mov	x1, #0
	cbz	w10, 1f
	mul	x1, x20, x9               ; the packet: ms x rate / (1000 x frames)
	mov	x11, #1000
	mul	x10, x10, x11
	udiv	x1, x1, x10
1:	str	x1, [sp, #24]
	ldr	x0, [x19, #TR_AFS]
	mov	x2, sp
	add	x3, sp, #8
	str	wzr, [sp, #8]
	bl	_AudioFileStreamSeek
	cbnz	w0, 2f
	mov	w0, #(AFS_DOFF & 0xffff)
	movk	w0, #(AFS_DOFF >> 16), lsl #16
	add	x1, sp, #16
	bl	afs_get
	ldp	x9, x10, [sp]             ; the byte, the data's start
	ldr	x10, [sp, #16]
	add	x9, x9, x10
	str	x9, [x19, #TR_OFF]
	ldr	x9, [sp, #24]             ; that packet's time
	ldr	w10, [x19, #TR_ASR]
	ldr	w11, [x19, #TR_AFPP]
	ldr	w12, [x19, #TR_TS]
	mul	x9, x9, x11
	mul	x9, x9, x12
	udiv	x9, x9, x10
	str	x9, [x19, #TR_APTS]
	mov	w9, #1
	str	w9, [x19, #TR_AFLAG]
	b	Lret1
2:	str	xzr, [x19, #TR_OFF]       ; it cannot seek: from the start
	str	xzr, [x19, #TR_APTS]
	mov	w9, #1
	str	w9, [x19, #TR_AFLAG]
	b	Lret1

; afs_stream(stream) — a web stream of sound: one track it feeds through an AudioFileStream (its type sniffed); no picture waited for.
afs_stream:
	FRAME	1
	mov	x19, x0
	mov	w9, #2
	str	w9, [x19, #ST_KIND]
	mov	w1, #'a'
	mov	w2, #(90000 & 0xffff)
	movk	w2, #(90000 >> 16), lsl #16
	bl	trk_new
	cbz	x0, Lret1
	str	xzr, [x0, #TR_APTS]
	mov	w1, #0
	bl	afs_open
	mov	x0, x19
	bl	no_pic
	b	Lret1

; afs_sfeed(stream, bytes, length) — a sound stream's bytes to its track's AudioFileStream; its length once it can tell.
afs_sfeed:
	FRAME	1
	ldr	x9, [x0, #ST_SPOS]
	add	x9, x9, x2
	str	x9, [x0, #ST_SPOS]
	ldr	x19, [x0, #ST_TR]
	cbz	x19, Lret1
	ldr	x9, [x19, #TR_OFF]        ; bytes read so far, for its length
	add	x9, x9, x2
	str	x9, [x19, #TR_OFF]
	mov	x0, x19
	mov	x3, #-1
	bl	afs_feed
	ldr	x9, [x27, #E_DURMS]
	ldr	x10, [x19, #TR_FD]
	cmp	x9, #0
	ccmp	x10, #0, #4, eq
	b.eq	Lret1
	bl	afs_dur
	b	Lret1

; no_pic(stream) — the media's first stream has no picture: the clock waits for none.
no_pic:
	BADDR	x9, E_ST
	ldr	x10, [x27, #E_VT]
	cmp	x0, x9
	ccmp	x10, #0, #0, eq
	b.ne	1f
	str	wzr, [x27, #E_WANTV]
1:	ret

; afs_open(track, hint) — the track's packets will come from an AudioFileStream; its format when the stream is ready.
afs_open:
	FRAME	0
	mov	w3, w1
	add	x4, x0, #TR_AFS
	adr	x1, afs_prop
	adr	x2, afs_pkts
	bl	_AudioFileStreamOpen
	b	Lret0

; afs_feed(track, bytes, length, pts) — bytes for its AudioFileStream; pts (track units, after the timeline's shift) times the packets that follow, -1 to go on.
afs_feed:
	FRAME	0
	tbnz	x3, #63, 1f
	str	x3, [x0, #TR_APTS]
1:	ldr	w3, [x0, #TR_AFLAG]      ; a discontinuity after a seek
	str	wzr, [x0, #TR_AFLAG]
	ldr	x0, [x0, #TR_AFS]
	cbz	x0, Lret0
	mov	x9, x1
	mov	w1, w2
	mov	x2, x9
	bl	_AudioFileStreamParseBytes
	b	Lret0

; afs_prop(track, stream, property, flags) — ready to produce packets: the track's format from the stream's data format and magic cookie.
	.equ AP_SIZE,	48
	.equ AP_FD,	56
	ENTRY	afs_prop
	FRAME	2, 64
	mov	x19, x0
	mov	x20, x1
	mov	w9, #(AFS_READY & 0xffff)
	movk	w9, #(AFS_READY >> 16), lsl #16
	cmp	w2, w9
	b.ne	Lret2
	mov	w9, #40
	str	w9, [sp, #AP_SIZE]
	mov	x0, x20
	mov	w1, #(AFS_FORMAT & 0xffff)
	movk	w1, #(AFS_FORMAT >> 16), lsl #16
	add	x2, sp, #AP_SIZE
	mov	x3, sp
	bl	_AudioFileStreamGetProperty
	cbnz	w0, Lret2
	mov	x21, #0                   ; its magic cookie, if it has one
	mov	x22, #0
	mov	x0, x20
	mov	w1, #(AFS_COOKIE & 0xffff)
	movk	w1, #(AFS_COOKIE >> 16), lsl #16
	add	x2, sp, #AP_SIZE
	add	x3, sp, #AP_FD
	bl	_AudioFileStreamGetPropertyInfo
	cbnz	w0, 1f
	ldr	w22, [sp, #AP_SIZE]
	mov	x0, x22
	bl	_malloc
	mov	x21, x0
	cbz	x0, 1f
	mov	x0, x20
	mov	w1, #(AFS_COOKIE & 0xffff)
	movk	w1, #(AFS_COOKIE >> 16), lsl #16
	add	x2, sp, #AP_SIZE
	mov	x3, x21
	bl	_AudioFileStreamGetProperty
	cmp	w0, #0
	csel	x22, x22, xzr, eq
1:	mov	x0, #0
	mov	x1, sp
	mov	x2, #0
	mov	x3, #0
	mov	x4, x22
	mov	x5, x21
	mov	x6, #0
	add	x7, sp, #AP_FD
	bl	_CMAudioFormatDescriptionCreate
	mov	w20, w0
	mov	x0, x21
	bl	_free
	cbnz	w20, Lret2
	ldr	x0, [x19, #TR_FD]
	cbz	x0, 2f
	bl	_CFRelease
2:	ldr	x0, [sp, #AP_FD]
	str	x0, [x19, #TR_FD]
	ldr	d0, [sp]                  ; rate and frames per packet
	fcvtzu	w9, d0
	ldr	w10, [sp, #20]
	cmp	w10, #0
	csinc	w10, w10, wzr, ne
	str	w9, [x19, #TR_ASR]
	str	w10, [x19, #TR_AFPP]
	b	Lret2

; afs_pkts(track, bytes, packets, data, descriptions) — packets found: one sound sample buffer of them, timed from TR_APTS, cut before a seek's target, queued.
	.equ AK_SB,	16
	.equ AK_BB,	24
	.equ AK_PTS,	32
	ENTRY	afs_pkts
	FRAME	3, 64
	mov	x19, x0
	ldr	x9, [x19, #TR_FD]
	cbz	x9, Lret3
	mov	w20, w1
	mov	w21, w2
	mov	x22, x3
	mov	x23, x4
	mov	x0, x20
	bl	_malloc
	cbz	x0, Lret3
	mov	x24, x0
	mov	x1, x22
	mov	x2, x20
	bl	_memcpy
	add	x9, sp, #AK_BB
	str	x9, [sp]
	mov	x0, #0
	mov	x1, x24
	mov	x2, x20
	mov	x3, #0                    ; freed with the sample
	mov	x4, #0
	mov	x5, #0
	mov	x6, x20
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbz	w0, 1f
	mov	x0, x24
	bl	_free
	b	Lret3
1:	ldr	x22, [x19, #TR_APTS]
	ldr	w9, [x19, #TR_TS]
	orr	x9, x9, #(1 << 32)
	stp	x22, x9, [sp, #AK_PTS]
	str	xzr, [sp, #(AK_PTS + 16)]
	mov	x0, #0
	ldr	x1, [sp, #AK_BB]
	ldr	x2, [x19, #TR_FD]
	mov	x3, x21
	add	x4, sp, #AK_PTS
	mov	x5, x23
	add	x6, sp, #AK_SB
	bl	_CMAudioSampleBufferCreateReadyWithPacketDescriptions
	mov	w24, w0
	ldr	x0, [sp, #AK_BB]
	bl	_CFRelease
	cbnz	w24, Lret3
	ldr	w9, [x19, #TR_AFPP]       ; their length: packets x frames x timescale / rate
	umull	x9, w9, w21
	ldr	w10, [x19, #TR_TS]
	mul	x9, x9, x10
	ldr	w10, [x19, #TR_ASR]
	cmp	w10, #0
	csinc	w10, w10, wzr, ne
	udiv	x23, x9, x10
	add	x9, x22, x23
	str	x9, [x19, #TR_APTS]
	str	x22, [x19, #TR_LAST]
	ldr	x9, [x19, #TR_TGT]
	subs	x1, x9, x22
	b.le	2f
	ldr	x0, [sp, #AK_SB]          ; before the target: decoded, cut
	mov	x2, x23
	bl	trim
2:	ldr	x0, [sp, #AK_SB]
	bl	q_push
	b	Lret3

; trim(sample, amount, duration) — the sound sample's first min(amount, duration) is decoded, not heard (x19 = track).
trim:
	FRAME	2, 32
	mov	x20, x0
	cmp	x1, x2
	csel	x1, x1, x2, lo
	ldr	w9, [x19, #TR_TS]
	orr	x9, x9, #(1 << 32)
	stp	x1, x9, [sp]
	str	xzr, [sp, #16]
	mov	x0, sp
	mov	x1, #0
	bl	_CMTimeCopyAsDictionary
	mov	x21, x0
	mov	x0, x20
	ldr	x1, [x27, #F_kCMSampleBufferAttachmentKey_TrimDurationAtStart]
	ldr	x1, [x1]
	mov	x2, x21
	mov	w3, #1                    ; kCMAttachmentMode_ShouldPropagate
	bl	_CMSetAttachment
	mov	x0, x21
	bl	_CFRelease
	b	Lret2

; pa_feed(stream, bytes, length) — packed audio (AAC, MPEG audio, AC-3 frames): each segment's ID3 tag times its first frame.
pa_feed:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	mov	x23, #-1                  ; no time: the packets go on
	ldr	x9, [x19, #ST_GOT]
	cmp	x9, x21
	b.ne	Lpa_feed                  ; not the segment's first bytes
	ldrb	w9, [x20]
	cmp	w9, #'I'
	b.ne	Lpa_track
	mov	x0, x20
	mov	x1, x21
	bl	id3_pts
	cmp	x0, x21
	csel	x0, x0, x21, lo
	add	x20, x20, x0              ; past the tag
	sub	x21, x21, x0
	tbnz	x1, #63, Lpa_track
	ldr	x9, [x27, #E_T0]          ; the timeline: anchored at the first time stamp
	tbz	x9, #63, 1f
	ldr	x10, [x19, #ST_SEGT]
	mov	x11, #90
	msub	x9, x10, x11, x1
	str	x9, [x27, #E_T0]
1:	sub	x23, x1, x9
Lpa_track:
	ldr	x22, [x19, #ST_AT]
	cbnz	x22, Lpa_feed
	cbz	x21, Lret3
	mov	x0, x19                   ; the first segment: a sound track, its stream hinted by the first frame's sync
	mov	w1, #'a'
	mov	w2, #(90000 & 0xffff)
	movk	w2, #(90000 >> 16), lsl #16
	bl	trk_new
	cbz	x0, Lret3
	mov	x22, x0
	str	x22, [x19, #ST_AT]
	ldrb	w9, [x20]
	TYPE	w1, 'a','c','-','3'       ; 0x0b 0x77: AC-3
	cmp	w9, #0x0b
	b.eq	2f
	TYPE	w1, 'M','P','G','3'       ; MPEG audio
	ldrb	w9, [x20, #1]
	mov	w10, #0xf6
	and	w9, w9, w10
	cmp	w9, #0xf0
	b.ne	2f
	TYPE	w1, 'a','d','t','s'       ; ADTS
2:	rev	w1, w1                    ; a four-character code
	mov	x0, x22
	bl	afs_open
Lpa_feed:
	ldr	x0, [x19, #ST_AT]
	cbz	x0, Lret3
	ldr	x9, [x0, #TR_APTS]        ; no time stamp and none yet (a start or a seek): its segment's start
	and	x9, x9, x23
	tbz	x9, #63, 3f
	ldr	x23, [x19, #ST_SEGT]
	mov	x9, #90
	mul	x23, x23, x9
3:	mov	x1, x20
	mov	x2, x21
	mov	x3, x23
	bl	afs_feed
	b	Lret3

; id3_pts(data, length) -> x0 = an ID3 tag's length, x1 = its Apple transport stream time stamp (90 kHz), or -1.
id3_pts:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	x21, #-1
	mov	x22, #0
	cmp	x20, #10
	b.lo	3f
	ldrb	w9, [x19, #6]             ; size: four 7-bit bytes, after the 10-byte header
	ldrb	w10, [x19, #7]
	ldrb	w11, [x19, #8]
	ldrb	w12, [x19, #9]
	orr	w12, w12, w11, lsl #7
	orr	w12, w12, w10, lsl #14
	orr	w12, w12, w9, lsl #21
	add	x22, x12, #10
	cmp	x22, x20
	csel	x20, x22, x20, lo
	add	x20, x19, x20             ; where the frames end
	add	x19, x19, #10
1:	add	x9, x19, #64
	cmp	x9, x20
	b.hi	3f
	ldr	w9, [x19]
	ldr	w10, [x19, #4]
	rev	w10, w10                  ; the frame's size
	TYPE	w11, 'P','R','I','V'
	cmp	w9, w11
	b.ne	2f
	add	x0, x19, #10
	CSTR	x1, "com.apple.streaming.transportStreamTimestamp"
	mov	x2, #45
	bl	_strncmp
	cbnz	w0, 2f
	ldur	x21, [x19, #55]
	rev	x21, x21
	and	x21, x21, #0x1ffffffff
	b	3f
2:	add	x19, x19, #10
	add	x19, x19, x10
	b	1b
3:	mov	x0, x22
	mov	x1, x21
	b	Lret2

; ---- Engine: This Mac's own player. Sample tables are read in place from the mapped file; CoreMedia's renderers decode, show and play on one clock ----

; The blocks the renderers call for more media: global, so their state is B's.
	.pushsection __DATA,__data
	.p2align 3
Lblk_v:	.quad	0                         ; isa: _NSConcreteGlobalBlock, set by main
	.long	0x50000000                ; global, with a signature
	.long	0
	.quad	feed_v
	.quad	Lblk_desc
Lblk_a:	.quad	0
	.long	0x50000000
	.long	0
	.quad	feed_a
	.quad	Lblk_desc
Lblk_s:	.quad	0
	.long	0x50000000
	.long	0
	.quad	sub_tick
	.quad	Lblk_desc
Lblk_desc:	.quad	0, 32, Lblk_sig
	.popsection
	.pushsection __TEXT,__cstring,cstring_literals
Lblk_sig:	.asciz	"v8@?0"
	.popsection

; unmap_cb(refcon, memory, size) — a released file mapping.
	ENTRY	unmap_cb
	mov	x0, x1
	mov	x1, x2
	b	_munmap

; eng_cmd(work, context) — run work(context) on the media queue.
eng_cmd:
	mov	x2, x0
	ldr	x0, [x28, #G_MEDIAQ]
	b	_dispatch_async_f

; eng_init — the synchronizer and its two renderers, made on the media queue: the first costs ~45 ms of framework setup, off the launch path.
	ENTRY	eng_init
	FRAME	1, 64
	CLASS	x0, AVSampleBufferRenderSynchronizer
	SEND	S_new
	str	x0, [x27, #E_SYNC]
	mov	x9, #1                    ; subtitles follow the clock every 1/30 s, and on every jump
	mov	x10, #30
	movk	x10, #1, lsl #32
	stp	x9, x10, [sp]
	str	xzr, [sp, #16]
	mov	x2, sp
	ldr	x3, [x28, #G_MEDIAQ]
	ADDR	x4, Lblk_s
	SEND	S_addPeriodicTimeObserverForInterval_queue_usingBlock_
	SEND	S_retain
	CLASS	x0, AVSampleBufferAudioRenderer
	SEND	S_new
	str	x0, [x27, #E_AR]
	mov	x19, x0
	CSTR	x0, "Spectral"            ; speed changes keep the pitch
	bl	mkstr
	mov	x2, x0
	mov	x0, x19
	SEND	S_setAudioTimePitchAlgorithm_
	mov	x2, x19
	ldr	x0, [x27, #E_SYNC]
	SEND	S_addRenderer_
	CLASS	x0, AVSampleBufferDisplayLayer
	SEND	S_new
	str	x0, [x28, #G_SBLAYER]
	mov	x19, x0
	CSTR	x0, "AVLayerVideoGravityResize" ; pic_layout gives it the picture's shape
	bl	mkstr
	mov	x2, x0
	mov	x0, x19
	SEND	S_setVideoGravity_
	mov	x0, x19
	SEND	S_sampleBufferRenderer
	str	x0, [x27, #E_VR]
	mov	x2, x0
	ldr	x0, [x27, #E_SYNC]
	SEND	S_addRenderer_
	bl	Leng_vol
	adr	x9, Lvt_sps               ; VideoToolbox's H.264 and HEVC decoders loaded off the launch path: a first picture ~60 ms sooner
	adr	x10, Lvt_pps
	stp	x9, x10, [sp]
	mov	x9, #(Lvt_pps - Lvt_sps)
	mov	x10, #(Lvt_vps - Lvt_pps)
	stp	x9, x10, [sp, #16]
	mov	x0, #0
	mov	x1, #2
	mov	x2, sp
	add	x3, sp, #16
	mov	w4, #4
	add	x5, sp, #48
	bl	_CMVideoFormatDescriptionCreateFromH264ParameterSets
	bl	vt_warm
	adr	x9, Lvt_vps
	adr	x10, Lvt_hsps
	stp	x9, x10, [sp]
	adr	x9, Lvt_hpps
	str	x9, [sp, #16]
	mov	x9, #(Lvt_hsps - Lvt_vps)
	mov	x10, #(Lvt_hpps - Lvt_hsps)
	stp	x9, x10, [sp, #24]
	mov	x9, #(Lvt_end - Lvt_hpps)
	str	x9, [sp, #40]
	mov	x0, #0
	mov	x1, #3
	mov	x2, sp
	add	x3, sp, #24
	mov	w4, #4
	mov	x5, #0
	add	x6, sp, #48
	bl	_CMVideoFormatDescriptionCreateFromHEVCParameterSets
	bl	vt_warm
	CLASS	x0, NSOperationQueue      ; the session calls its delegate on the media queue
	SEND	S_new
	mov	x19, x0
	ldr	x2, [x28, #G_MEDIAQ]
	SEND	S_setUnderlyingQueue_
	CLASS	x0, NSURLSessionConfiguration
	SEND	S_defaultSessionConfiguration
	mov	x2, x0
	ldr	x3, [x28, #G_CTRL]
	mov	x4, x19
	CLASS	x0, NSURLSession
	SEND	S_sessionWithConfiguration_delegate_delegateQueue_
	SEND	S_retain
	str	x0, [x27, #E_SESSION]
	adr	x0, ui_attach
	mov	x1, #0
	bl	post_main
	b	Lret1

Lvt_sps:	.byte	0x67, 0x42, 0xc0, 0x0a, 0xd9, 0x07, 0x3c, 0xc0, 0x44, 0x00, 0x00, 0x03, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x08, 0x3c, 0x48, 0x99, 0x20
Lvt_pps:	.byte	0x68, 0xcb, 0x83, 0xcb, 0x20
Lvt_vps:	.byte	0x40, 0x01, 0x0c, 0x01, 0xff, 0xff, 0x01, 0x60, 0x00, 0x00, 0x03, 0x00, 0xb0, 0x00, 0x00, 0x03, 0x00, 0x00, 0x03, 0x00, 0x99, 0x15, 0xc0, 0x90
Lvt_hsps:	.byte	0x42, 0x01, 0x01, 0x01, 0x60, 0x00, 0x00, 0x03, 0x00, 0xb0, 0x00, 0x00, 0x03, 0x00, 0x00, 0x03, 0x00, 0x99, 0xa0, 0x01, 0xe0, 0x20, 0x02, 0x1c, 0x58, 0x81, 0x5e, 0xe4, 0x59, 0x51
Lvt_hpps:	.byte	0x44, 0x01, 0xc0, 0x2c, 0xbc, 0x14, 0xc9
Lvt_end:
	.p2align 2

; vt_warm(status) — after a format was made at sp + 48 (status 0): a decompression session for it made and dropped, so VideoToolbox's decoder is loaded early; the format released (in eng_init's frame).
vt_warm:
	cbnz	w0, 2f
	stp	x29, x30, [sp, #-16]!
	mov	x0, #0
	ldr	x1, [sp, #(16 + 48)]
	mov	x2, #0
	mov	x3, #0
	mov	x4, #0
	add	x5, sp, #(16 + 56)
	bl	_VTDecompressionSessionCreate
	cbnz	w0, 1f
	ldr	x0, [sp, #(16 + 56)]
	bl	_VTDecompressionSessionInvalidate
	ldr	x0, [sp, #(16 + 56)]
	bl	_CFRelease
1:	ldr	x0, [sp, #(16 + 48)]
	bl	_CFRelease
	ldp	x29, x30, [sp], #16
2:	ret

; ui_attach — the engine's layer goes into its view.
	ENTRY	ui_attach
	FRAME	0
	ADDR	x0, Lprog_attach
	bl	ui_run
	bl	pic_layout
	b	Lret0

; ui_poll — re-render now.
	ENTRY	ui_poll
	b	local_poll

; eng_close — stop and forget the open file; its mapping goes once the renderers let go of its samples.
	ENTRY	eng_close
	FRAME	1
	ldr	x0, [x27, #E_SYNC]
	movi	d0, #0
	SEND	S_setRate_
	ldr	x0, [x27, #E_VR]
	SEND	S_stopRequestingMediaData
	ldr	x0, [x27, #E_VR]
	mov	w2, #1                    ; the last picture goes too
	mov	x3, #0
	SEND	S_flushWithRemovalOfDisplayedImage_completionHandler_
	ldr	x0, [x27, #E_AR]
	SEND	S_stopRequestingMediaData
	ldr	x0, [x27, #E_AR]
	SEND	S_flush
	bl	sub_reset
	BADDR	x0, E_ST
	bl	st_close
	BADDR	x0, (E_ST + ST_SIZE)
	bl	st_close
	BADDR	x0, (E_ST + 2 * ST_SIZE)
	bl	st_close
	ldr	x0, [x27, #E_MASTER]
	bl	_free
	ldr	x0, [x27, #E_MURL]
	bl	_free
	BADDR	x19, E_TR
	add	x20, x19, #((TRACKS * TR_SIZE) >> 12), lsl #12
Lec_fd:
	ldr	x0, [x19, #TR_FD]
	cbz	x0, 1f
	bl	_CFRelease
1:	ldr	x0, [x19, #TR_AFS]
	cbz	x0, 2f
	bl	_AudioFileStreamClose
2:	bl	q_clear
	ldr	x0, [x19, #TR_FQ]
	bl	_free
	ldr	x0, [x19, #TR_FL]
	bl	_free
	add	x19, x19, #TR_SIZE
	cmp	x19, x20
	b.lo	Lec_fd
	ldr	x0, [x27, #E_PARENT]
	cbz	x0, 1f
	bl	_CFRelease
1:	BADDR	x0, E_CLR
	mov	x1, #E_CLRN
	bl	_bzero
	b	Lret1

; eng_open(request) — play a file on This Mac from its start; request = {play generation, path}, freed here. What it cannot read, AVPlayer gets (eng_fallback).
	ENTRY	eng_open
	FRAME	2, 176                    ; the 9th argument at sp, struct stat at sp + 16
	mov	x19, x0
	bl	Leng_close
	add	x0, x19, #8
	mov	w1, #0                    ; O_RDONLY
	bl	_open
	mov	w20, w0
	tbnz	w0, #31, Leo_fail
	add	x1, sp, #16
	bl	_fstat
	ldr	x21, [sp, #(16 + STAT_SIZE)]
	cbnz	w0, Leo_close
	mov	x0, #0
	mov	x1, x21
	mov	w2, #PROT_READ
	mov	w3, #MAP_PRIVATE
	mov	w4, w20
	mov	x5, #0
	bl	_mmap
	mov	x22, x0
	mov	w0, w20
	bl	_close
	cmn	x22, #1
	b.eq	Leo_fail                  ; MAP_FAILED, e.g. an empty file
	str	x22, [x27, #E_MAP]
	str	x21, [x27, #E_LEN]
	mov	x0, x22
	mov	x1, x21
	mov	w2, #MADV_SEQUENTIAL
	bl	_madvise
	BADDR	x9, E_PARENT
	str	x9, [sp]
	stp	xzr, xzr, [sp, #16]       ; CMBlockBufferCustomBlockSource, packed to 4 (CoreMedia copies it): the mapping goes with the last sample
	adr	x9, unmap_cb
	stur	x9, [sp, #(16 + 12)]      ; FreeBlock
	stur	xzr, [sp, #(16 + 20)]     ; refCon
	mov	x0, #0
	mov	x1, x22
	mov	x2, x21
	mov	x3, #0
	add	x4, sp, #16
	mov	x5, #0
	mov	x6, x21
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbz	w0, Leo_read
	mov	x0, x22                   ; no buffer to own it: unmap here
	mov	x1, x21
	bl	_munmap
	b	Leo_fail
Leo_read:
	bl	mp4_open
	cbnz	w0, 1f
	bl	afs_file                  ; not MP4: a sound file AudioFileStream reads
	cbz	w0, Leo_fail
1:	ldr	w9, [x19]
	str	w9, [x27, #E_GEN]
	ldr	x9, [x27, #E_VT]
	cmp	x9, #0
	cset	w9, ne
	str	w9, [x27, #E_WANTV]
	mov	x0, x19
	bl	_free
	mov	x0, #0
	bl	Leng_seek                 ; from the start
	adr	x0, ui_poll
	mov	x1, #0
	bl	post_main
	b	Lret2
Leo_close:
	mov	w0, w20
	bl	_close
Leo_fail:
	bl	Leng_close
	ldr	w20, [x19]
	mov	x0, x19
	bl	_free
	adr	x0, eng_fallback
	mov	x1, x20
	bl	post_main
	b	Lret2

; eng_fallback(generation) — the engine cannot play This Mac's file: AVPlayer tries it, unless a newer play came (main).
	ENTRY	eng_fallback
	FRAME	1
	ldr	w9, [x28, #G_PLAYGEN]
	cmp	w0, w9
	b.ne	Lret1
	mov	w9, #1
	str	w9, [x28, #G_MODE]
	adr	x0, eng_close
	mov	x1, #0
	bl	eng_cmd
	BADDR	x0, B_LTPATH
	ldrb	w9, [x0]
	cmp	w9, #'/'
	b.eq	1f
	bl	mkurl                     ; web media
	b	2f
1:	bl	mkstr
	mov	x2, x0
	CLASS	x0, NSURL
	SEND	S_fileURLWithPath_
2:	mov	x2, x0
	CLASS	x0, AVPlayerItem
	SEND	S_playerItemWithURL_
	mov	x2, x0
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_replaceCurrentItemWithPlayerItem_
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_play
	bl	local_poll
	b	Lret1

; mp4_open() -> w0 = 1 when the mapped file is an MP4 or QuickTime movie with a picture or sound CoreMedia knows: its tracks are read and the first of each kind plays.
mp4_open:
	FRAME	4
	ldr	x19, [x27, #E_MAP]
	ldr	x9, [x27, #E_LEN]
	add	x20, x19, x9
	mov	x0, x19
	mov	x1, x20
	TYPE	w2, 'f','t','y','p'
	bl	box_find
	cbz	x0, Lmo_moov              ; none: QuickTime
	add	x9, x0, #4
	cmp	x9, x1
	b.hi	Lmo_moov
	ldr	w9, [x0]                  ; the major brand
	TYPE	w10, 'q','t',' ',' '
	cmp	w9, w10
	cset	w9, ne
	str	w9, [x27, #E_ISO]
Lmo_moov:
	mov	x0, x19
	mov	x1, x20
	TYPE	w2, 'm','o','o','v'
	bl	box_find
	cbz	x0, Lmo_no
	mov	x21, x0
	mov	x22, x1
	TYPE	w2, 'm','v','h','d'
	bl	box_find
	cbz	x0, Lmo_no
	add	x9, x0, #32
	cmp	x9, x1
	b.hi	Lmo_no
	ldrb	w9, [x0]                  ; version: 32- or 64-bit times
	ldr	w10, [x0, #12]
	ldr	w11, [x0, #16]
	rev	w11, w11
	cbz	w9, 1f
	ldr	w10, [x0, #20]
	ldr	x11, [x0, #24]
	rev	x11, x11
1:	rev	w10, w10                  ; movie timescale
	cbz	w10, Lmo_no
	str	w10, [x27, #E_MTS]
	mov	x12, #1000
	mul	x11, x11, x12
	udiv	x11, x11, x10
	str	x11, [x27, #E_DURMS]
	mov	x23, x21
Lmo_trak:
	mov	x0, x23
	mov	x1, x22
	TYPE	w2, 't','r','a','k'
	bl	box_find
	cbz	x0, Lmo_pick
	mov	x23, x1                   ; the next one starts after it
	mov	w2, #0
	mov	x3, #0
	bl	trak_open
	b	Lmo_trak
Lmo_pick:
	BADDR	x9, E_TR
	add	x10, x9, #((TRACKS * TR_SIZE) >> 12), lsl #12
Lmo_each:
	ldr	w11, [x9, #TR_KIND]
	cmp	w11, #'v'
	b.ne	1f
	ldr	x12, [x27, #E_VT]
	cbnz	x12, 1f
	str	x9, [x27, #E_VT]
1:	cmp	w11, #'a'
	b.ne	2f
	ldr	x12, [x27, #E_AT]
	cbnz	x12, 2f
	str	x9, [x27, #E_AT]
2:	add	x9, x9, #TR_SIZE
	cmp	x9, x10
	b.lo	Lmo_each
	ldr	x9, [x27, #E_VT]
	ldr	x10, [x27, #E_AT]
	orr	x9, x9, x10
	cmp	x9, #0
	cset	w0, ne
	b	Lret4
Lmo_no:
	mov	w0, #0
	b	Lret4

; trak_open(trak, end, fragmented, track) -> x0 = the track (the next free one if 0), read: kind, timescale, edit, tables (empty when fragmented) and format; 0 for one this player cannot use.
trak_open:
	FRAME	4
	mov	x20, x0
	mov	x21, x1
	mov	w26, w2
	mov	x19, x3
	cbnz	x19, 1f
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Lto_no
	add	w10, w9, #1
	str	w10, [x27, #E_NTR]
	BADDR	x19, E_TR
	add	x19, x19, x9, lsl #9      ; TR_SIZE
1:	TYPE	w2, 't','k','h','d'
	bl	box_find
	cbz	x0, Lto_no
	add	x9, x0, #24
	cmp	x9, x1
	b.hi	Lto_no
	ldrb	w9, [x0]
	ldr	w10, [x0, #12]
	cbz	w9, 1f
	ldr	w10, [x0, #20]
1:	rev	w10, w10
	str	w10, [x19, #TR_ID]
	add	x11, x0, #40              ; its matrix's first column: the turn
	cbz	w9, 2f
	add	x11, x0, #52
2:	add	x12, x11, #8
	cmp	x12, x1
	b.hi	3f
	ldp	w12, w13, [x11]
	rev	w12, w12                  ; cos
	rev	w13, w13                  ; sin, with y down
	cmp	w13, #0
	mov	w14, #-90
	csel	w14, w14, wzr, gt
	mov	w15, #90
	csel	w14, w15, w14, lt
	cmp	w12, #0
	mov	w15, #180
	csel	w14, w15, w14, lt
	str	w14, [x19, #TR_ROT]
3:	mov	x0, x20
	mov	x1, x21
	TYPE	w2, 'm','d','i','a'
	bl	box_find
	cbz	x0, Lto_no
	mov	x22, x0
	mov	x23, x1
	TYPE	w2, 'h','d','l','r'
	bl	box_find
	cbz	x0, Lto_no
	add	x9, x0, #12
	cmp	x9, x1
	b.hi	Lto_no
	ldr	w24, [x0, #8]             ; the handler: 'vide', 'soun', ...
	mov	x0, x22
	mov	x1, x23
	TYPE	w2, 'm','d','h','d'
	bl	box_find
	cbz	x0, Lto_no
	add	x9, x0, #24
	cmp	x9, x1
	b.hi	Lto_no
	ldrb	w9, [x0]
	ldr	w10, [x0, #12]
	cbz	w9, 1f
	ldr	w10, [x0, #20]
1:	rev	w10, w10
	cbz	w10, Lto_no
	str	w10, [x19, #TR_TS]
	add	x11, x0, #20              ; its language: three letters, 5 bits each
	cbz	w9, 2f
	add	x11, x0, #32
2:	add	x12, x11, #2
	cmp	x12, x1
	b.hi	3f
	ldrh	w12, [x11]
	rev16	w12, w12
	cmp	w12, #0x400               ; below: a QuickTime language number
	b.lo	3f
	ubfx	w13, w12, #10, #5
	ubfx	w14, w12, #5, #5
	and	w15, w12, #31
	add	w13, w13, #0x60
	add	w14, w14, #0x60
	add	w15, w15, #0x60
	orr	w13, w13, w14, lsl #8
	orr	w13, w13, w15, lsl #16
	TYPE	w14, 'u','n','d',0
	cmp	w13, w14
	csel	w13, w13, wzr, ne         ; "und": none
	str	w13, [x19, #TR_LANG]
3:	mov	x0, x22
	mov	x1, x23
	TYPE	w2, 'm','i','n','f'
	bl	box_find
	cbz	x0, Lto_no
	TYPE	w2, 's','t','b','l'
	bl	box_find
	cbz	x0, Lto_no
	mov	x22, x0
	mov	x23, x1
	TYPE	w2, 's','t','s','d'
	bl	box_find
	cbz	x0, Lto_no
	add	x9, x0, #12
	cmp	x9, x1
	b.hi	Lto_no
	ldr	w10, [x0, #8]
	rev	w10, w10                  ; the first description's size
	sub	x11, x1, x0
	sub	x11, x11, #8
	cmp	x10, #16
	ccmp	x10, x11, #2, hs
	b.hi	Lto_no
	add	x0, x0, #8
	str	x0, [x19, #TR_STSD]
	str	w10, [x19, #TR_STSDN]
	adr	x25, Lstbl
Lto_tbl:
	ldr	w2, [x25]
	cbz	w2, Lto_tables
	mov	x0, x22
	mov	x1, x23
	bl	box_find
	cbz	x0, Lto_next
	ldrb	w9, [x25, #6]
	ldrb	w10, [x25, #7]
	add	x11, x0, x9
	ldur	w12, [x11, #-4]
	rev	w12, w12                  ; entries
	tbz	w10, #7, 1f
	ldr	w13, [x0, #4]
	cmp	w13, #0
	csel	w10, w10, wzr, eq         ; a fixed size: no table
1:	and	w10, w10, #0x7f
	umaddl	x11, w12, w10, x11
	cmp	x11, x1
	b.hi	Lto_no                     ; cut short: not a track to trust
	ldrb	w9, [x25, #4]
	str	x0, [x19, x9]
	ldrb	w9, [x25, #5]
	str	w12, [x19, x9]
Lto_next:
	add	x25, x25, #8
	b	Lto_tbl
Lto_tables:
	ldr	x9, [x19, #TR_STSZ]
	cbz	x9, Lto_no
	ldr	w10, [x9, #4]
	rev	w10, w10
	str	w10, [x19, #TR_FIXED]
	cbnz	w26, Lto_edit             ; fragmented: samples come later
	ldr	w9, [x19, #TR_N]
	ldr	w10, [x19, #TR_NST]
	ldr	w11, [x19, #TR_NSC]
	ldr	w12, [x19, #TR_NCH]
	cmp	w9, #0
	ccmp	w10, #0, #4, ne
	ccmp	w11, #0, #4, ne
	ccmp	w12, #0, #4, ne
	b.eq	Lto_no                     ; no samples, or a table missing
Lto_edit:
	mov	x0, x20
	mov	x1, x21
	TYPE	w2, 'e','d','t','s'
	bl	box_find
	cbz	x0, Lto_fmt
	TYPE	w2, 'e','l','s','t'
	bl	box_find
	cbz	x0, Lto_fmt
	bl	elst_shift
Lto_fmt:
	ldr	x0, [x19, #TR_FD]         ; a track read again lets its old format go
	str	xzr, [x19, #TR_FD]
	cbz	x0, 1f
	bl	_CFRelease
1:	mov	x0, #0
	ldr	x1, [x19, #TR_STSD]
	ldr	w2, [x19, #TR_STSDN]
	ldr	w9, [x27, #E_ISO]
	TYPE	w10, 'v','i','d','e'
	cmp	w24, w10
	b.eq	Lto_vide
	TYPE	w10, 's','o','u','n'
	cmp	w24, w10
	b.ne	Lto_text
	mov	x3, #0                    ; QuickTime
	cbz	w9, 1f
	ldr	x3, [x27, #F_kCMSoundDescriptionFlavor_ISOFamily]
	ldr	x3, [x3]
1:	add	x4, x19, #TR_FD
	bl	_CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData
	mov	w9, #'a'
	b	Lto_kind
Lto_vide:
	mov	w3, #0                    ; the compressor name's text encoding
	mov	x4, #0
	cbz	w9, 1f
	ldr	x4, [x27, #F_kCMImageDescriptionFlavor_ISOFamily]
	ldr	x4, [x4]
1:	add	x5, x19, #TR_FD
	bl	_CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData
	cbnz	w0, Lto_no
	bl	vid_dims
	mov	w0, #0
	mov	w9, #'v'
Lto_kind:
	cbnz	w0, Lto_no                 ; a format CoreMedia does not know
	str	w9, [x19, #TR_KIND]
	mov	x0, x19
	b	Lret4
Lto_no:
	mov	x0, #0
	b	Lret4
Lto_text:
	ldr	w3, [x1, #4]              ; subtitles or captions, known by their sample description
	adr	x10, Ltext
1:	ldr	w11, [x10], #4
	cbz	w11, Lto_no
	cmp	w3, w11
	b.ne	1b
	rev	w1, w3
	mov	w2, w1
	mov	x3, #0
	add	x4, x19, #TR_FD
	bl	_CMFormatDescriptionCreate
	mov	w9, #'s'
	b	Lto_kind
Ltext:	.ascii	"tx3gtextwvttc608"
	.long	0
	.p2align 2
Lstbl:	                                  ; box, where its payload and entry count go, header bytes, bytes per entry
	.ascii	"stts"
	.byte	TR_STTS, TR_NST, 8, 8
	.ascii	"ctts"
	.byte	TR_CTTS, TR_NCT, 8, 8
	.ascii	"stsc"
	.byte	TR_STSC, TR_NSC, 8, 12
	.ascii	"stsz"
	.byte	TR_STSZ, TR_N, 12, 0x84
	.ascii	"stco"
	.byte	TR_STCO, TR_NCH, 8, 4
	.ascii	"co64"
	.byte	TR_CO64, TR_NCH, 8, 8
	.ascii	"stss"
	.byte	TR_STSS, TR_NSS, 8, 4
	.long	0

; elst_shift(elst, end) — the track's start from its edit list: the first edit's media time, less a leading empty edit (x19 = track).
elst_shift:
	ldrb	w9, [x0]                  ; version: 32- or 64-bit fields
	ldr	w10, [x0, #4]
	rev	w10, w10                  ; edits
	add	x11, x0, #8
	mov	x12, #12
	cbz	w9, 1f
	mov	x12, #20
1:	mov	x15, #0                   ; empty edits, in movie units
Lel_edit:
	cbz	w10, Lel_none
	add	x13, x11, x12
	cmp	x13, x1
	b.hi	Lel_none
	cbnz	w9, 2f
	ldr	w13, [x11]
	rev	w13, w13
	ldr	w14, [x11, #4]
	rev	w14, w14
	sxtw	x14, w14
	b	3f
2:	ldr	x13, [x11]
	rev	x13, x13
	ldr	x14, [x11, #8]
	rev	x14, x14
3:	cmn	x14, #1
	b.ne	Lel_found
	add	x15, x15, x13             ; empty: the media starts later
	add	x11, x11, x12
	sub	w10, w10, #1
	b	Lel_edit
Lel_found:
	ldr	w9, [x19, #TR_TS]
	mul	x15, x15, x9
	ldr	w9, [x27, #E_MTS]
	udiv	x15, x15, x9
	sub	x14, x14, x15
	str	x14, [x19, #TR_SHIFT]
Lel_none:
	ret

; The cursor (x19 = track): sample I's size, duration, composition offset, sync flag and file offset, read from its tables as it steps.

; cur_size -> x0 = the sample's size.
cur_size:
	ldr	w0, [x19, #TR_FIXED]
	cbnz	w0, 1f
	ldr	x9, [x19, #TR_STSZ]
	ldr	w10, [x19, #TR_I]
	add	x9, x9, x10, lsl #2
	ldr	w0, [x9, #12]
	rev	w0, w0
1:	ret

; cur_delta -> x0 = the sample's duration.
cur_delta:
	ldr	x9, [x19, #TR_STTS]
	ldr	w10, [x19, #TR_STI]
	add	x9, x9, x10, lsl #3
	ldr	w0, [x9, #12]
	rev	w0, w0
	ret

; cur_cts -> x0 = the sample's composition offset.
cur_cts:
	mov	x0, #0
	ldr	w10, [x19, #TR_NCT]
	cbz	w10, 1f
	ldr	x9, [x19, #TR_CTTS]
	ldr	w10, [x19, #TR_CTI]
	add	x9, x9, x10, lsl #3
	ldr	w0, [x9, #12]
	rev	w0, w0
	sxtw	x0, w0
1:	ret

; cur_sync -> w0 = 1 for a sync sample (every one, without an stss).
cur_sync:
	mov	w0, #1
	ldr	x9, [x19, #TR_STSS]
	cbz	x9, 1f
	ldr	w10, [x19, #TR_SSI]
	ldr	w11, [x19, #TR_NSS]
	mov	w0, #0
	cmp	w10, w11
	b.hs	1f
	add	x9, x9, x10, lsl #2
	ldr	w9, [x9, #8]
	rev	w9, w9
	ldr	w10, [x19, #TR_I]
	add	w10, w10, #1
	cmp	w9, w10
	cset	w0, eq
1:	ret

; snap / unsnap — keep the cursor, or go back to the kept one.
snap:
	add	x9, x19, #TR_I
	add	x10, x19, #TR_SNAP
	b	Lsnap
unsnap:
	add	x9, x19, #TR_SNAP
	add	x10, x19, #TR_I
Lsnap:
	ld1	{ v0.16b, v1.16b, v2.16b, v3.16b }, [x9]
	st1	{ v0.16b, v1.16b, v2.16b, v3.16b }, [x10]
	ret

; cur_reset — to the first sample.
cur_reset:
	mov	w9, #-1
	stp	wzr, w9, [x19, #TR_I]     ; sample 0, before stts entry 0
	stp	wzr, w9, [x19, #TR_STL]   ; and ctts entry 0
	stp	wzr, wzr, [x19, #TR_CTL]
	stp	w9, wzr, [x19, #TR_CH]    ; chunk -1: cur_chunk takes it to 0
	str	wzr, [x19, #TR_SSI]
	str	xzr, [x19, #TR_DTS]
; cur_chunk — to the next chunk: its stsc entry, sample count and offset; then cur_norm.
cur_chunk:
	ldr	w9, [x19, #TR_CH]
	add	w9, w9, #1
	str	w9, [x19, #TR_CH]
	ldr	x10, [x19, #TR_STSC]
	ldr	w11, [x19, #TR_SCI]
	ldr	w13, [x19, #TR_NSC]
	add	w14, w9, #1               ; the chunk's number, from 1
Lcc_entry:
	add	w15, w11, #1
	cmp	w15, w13
	b.hs	Lcc_this
	mov	w16, #12
	umaddl	x16, w15, w16, x10
	ldr	w16, [x16, #8]
	rev	w16, w16                  ; the next entry's first chunk
	cmp	w16, w14
	b.hi	Lcc_this
	mov	w11, w15
	b	Lcc_entry
Lcc_this:
	str	w11, [x19, #TR_SCI]
	mov	w16, #12
	umaddl	x16, w11, w16, x10
	ldr	w16, [x16, #12]
	rev	w16, w16
	str	w16, [x19, #TR_CHL]
	mov	x10, #0x7fffffffffffffff  ; past the last chunk: nowhere
	ldr	w11, [x19, #TR_NCH]
	cmp	w9, w11
	b.hs	Lcc_off
	ldr	x10, [x19, #TR_CO64]
	cbz	x10, 1f
	add	x10, x10, x9, lsl #3
	ldr	x10, [x10, #8]
	rev	x10, x10
	b	Lcc_off
1:	ldr	x10, [x19, #TR_STCO]
	add	x10, x10, x9, lsl #2
	ldr	w10, [x10, #8]
	rev	w10, w10
Lcc_off:
	str	x10, [x19, #TR_OFF]
; cur_norm — past the stts and ctts runs a step used up, and stss up to the sample.
cur_norm:
	ldr	w9, [x19, #TR_STL]
	cbnz	w9, Lcn_ct
	ldr	w10, [x19, #TR_STI]
	add	w10, w10, #1
	ldr	w11, [x19, #TR_NST]
	cmp	w10, w11
	b.hs	Lcn_ct
	str	w10, [x19, #TR_STI]
	ldr	x11, [x19, #TR_STTS]
	add	x11, x11, x10, lsl #3
	ldr	w11, [x11, #8]
	rev	w11, w11
	str	w11, [x19, #TR_STL]
	b	cur_norm
Lcn_ct:
	ldr	w9, [x19, #TR_CTL]
	cbnz	w9, Lcn_ss
	ldr	w10, [x19, #TR_CTI]
	add	w10, w10, #1
	ldr	w11, [x19, #TR_NCT]
	cmp	w10, w11
	b.hs	Lcn_ss
	str	w10, [x19, #TR_CTI]
	ldr	x11, [x19, #TR_CTTS]
	add	x11, x11, x10, lsl #3
	ldr	w11, [x11, #8]
	rev	w11, w11
	str	w11, [x19, #TR_CTL]
	b	Lcn_ct
Lcn_ss:
	ldr	x9, [x19, #TR_STSS]
	cbz	x9, Lcn_done
	ldr	w10, [x19, #TR_SSI]
	ldr	w11, [x19, #TR_NSS]
	ldr	w12, [x19, #TR_I]
	add	w12, w12, #1
1:	cmp	w10, w11
	b.hs	2f
	add	x13, x9, x10, lsl #2
	ldr	w13, [x13, #8]
	rev	w13, w13
	cmp	w13, w12
	b.hs	2f
	add	w10, w10, #1
	b	1b
2:	str	w10, [x19, #TR_SSI]
Lcn_done:
	ret

; cur_step — on to the next sample.
cur_step:
	FRAME	0
	bl	cur_size
	mov	x12, x0
	bl	cur_delta
	ldr	x10, [x19, #TR_DTS]
	add	x10, x10, x0
	str	x10, [x19, #TR_DTS]
	ldr	w9, [x19, #TR_I]
	add	w9, w9, #1
	str	w9, [x19, #TR_I]
	ldr	w9, [x19, #TR_STL]
	sub	w9, w9, #1
	str	w9, [x19, #TR_STL]
	ldr	w9, [x19, #TR_CTL]
	sub	w9, w9, #1
	str	w9, [x19, #TR_CTL]
	ldr	w9, [x19, #TR_CHL]
	subs	w9, w9, #1
	str	w9, [x19, #TR_CHL]
	b.le	1f
	ldr	x10, [x19, #TR_OFF]
	add	x10, x10, x12
	str	x10, [x19, #TR_OFF]
	bl	cur_norm
	b	Lret0
1:	bl	cur_chunk
	b	Lret0

; cur_seek(target, run) — to the last sync sample at or before the one holding target (media units); run > 1 stops run - 1 samples earlier.
cur_seek:
	FRAME	2
	mov	x20, x0
	mov	w21, w1
	bl	cur_reset
	bl	snap
Lcs_step:
	ldr	w9, [x19, #TR_I]
	add	w9, w9, #1
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	Lcs_done                  ; the last sample
	bl	cur_delta
	ldr	x9, [x19, #TR_DTS]
	madd	x9, x0, x21, x9
	cmp	x9, x20
	b.gt	Lcs_done
	bl	cur_step
	bl	cur_sync
	cbz	w0, Lcs_step
	bl	snap
	b	Lcs_step
Lcs_done:
	bl	unsnap
	b	Lret2

; setflag(attachments, key) — attachments[*key] = kCFBooleanTrue.
setflag:
	ldr	x1, [x1]
	ldr	x2, [x27, #F_kCFBooleanTrue]
	ldr	x2, [x2]
	b	_CFDictionarySetValue

; mk_sample(bb, offset, size, dts, pts, duration, sync) -> a ready CMSampleBuffer (retained) over bb's bytes, marked for the track's target; 0 if it could not be made (x19 = track).
	.equ MS_TIME,	16                ; CMSampleTimingInfo: duration, presentation and decode times
	.equ MS_LEN,	88
	.equ MS_BB,	96
	.equ MS_SB,	104
mk_sample:
	FRAME	3, 112
	ldr	w9, [x19, #TR_KIND]       ; CC1 shown: a picture's SEI carries its captions
	ldr	x10, [x27, #E_SUBT]
	ldr	x11, [x27, #E_CCT]
	cmp	w9, #'v'
	ccmp	x10, x11, #0, eq
	ccmp	x10, #0, #4, eq
	b.eq	1f
	stp	x0, x1, [sp, #16]
	stp	x2, x3, [sp, #32]
	stp	x4, x5, [sp, #48]
	str	x6, [sp, #64]
	ldr	w9, [x19, #TR_TS]         ; its time on the captions' 90 kHz
	mov	x10, #(90000 & 0xffff)
	movk	x10, #(90000 >> 16), lsl #16
	mul	x3, x4, x10
	sdiv	x3, x3, x9
	bl	cc_avcc
	ldp	x0, x1, [sp, #16]
	ldp	x2, x3, [sp, #32]
	ldp	x4, x5, [sp, #48]
	ldr	x6, [sp, #64]
1:	str	x4, [x19, #TR_LAST]
	mov	x20, x4
	mov	x21, x5
	mov	w22, w6
	mov	x23, x3
	str	x2, [sp, #MS_LEN]
	mov	x3, x2
	mov	x2, x1
	mov	x1, x0
	mov	x0, #0
	mov	w4, #0
	add	x5, sp, #MS_BB
	bl	_CMBlockBufferCreateWithBufferReference
	cbnz	w0, Lms_none
	ldr	w24, [x19, #TR_TS]
	orr	x24, x24, #(1 << 32)      ; timescale, kCMTimeFlags_Valid
	stp	x21, x24, [sp, #MS_TIME]
	str	xzr, [sp, #(MS_TIME + 16)]
	stp	x20, x24, [sp, #(MS_TIME + 24)]
	str	xzr, [sp, #(MS_TIME + 40)]
	stp	x23, x24, [sp, #(MS_TIME + 48)]
	str	xzr, [sp, #(MS_TIME + 64)]
	add	x9, sp, #MS_SB
	str	x9, [sp]                  ; the 9th argument
	mov	x0, #0
	ldr	x1, [sp, #MS_BB]
	ldr	x2, [x19, #TR_FD]
	mov	x3, #1
	mov	x4, #1
	add	x5, sp, #MS_TIME
	mov	x6, #1
	add	x7, sp, #MS_LEN
	bl	_CMSampleBufferCreateReady
	mov	w23, w0
	ldr	x0, [sp, #MS_BB]
	bl	_CFRelease                ; the sample keeps it
	cbnz	w23, Lms_none
	ldr	x23, [sp, #MS_SB]
	mov	x0, x23
	mov	w1, #1
	bl	_CMSampleBufferGetSampleAttachmentsArray
	mov	x1, #0
	bl	_CFArrayGetValueAtIndex
	mov	x24, x0
	cbnz	w22, 1f
	ldr	x1, [x27, #F_kCMSampleAttachmentKey_NotSync]
	bl	setflag
1:	ldr	x9, [x19, #TR_TGT]
	subs	x9, x9, x20               ; how much of it is before the target
	b.le	Lms_shown
	ldr	w10, [x19, #TR_KIND]
	cmp	w10, #'v'
	b.ne	Lms_trim
	cmp	x21, #0                   ; a picture: hidden if it ends before the target (or its length is unknown)
	ccmp	x9, x21, #2, ne
	b.lo	Lms_shown                 ; the target falls in it: shown
	mov	x0, x23                   ; one no picture refers to is not even decoded
	bl	pic_ref
	cbnz	w0, 2f
	mov	x0, x23
	bl	_CFRelease
	b	Lms_none
2:	mov	x0, x24                   ; decoded, never shown
	ldr	x1, [x27, #F_kCMSampleAttachmentKey_DoNotDisplay]
	bl	setflag
	b	Lms_ok
Lms_shown:
	ldr	w10, [x19, #TR_KIND]      ; the earliest picture shown: a seek's clock may have to move to it
	cmp	w10, #'v'
	b.ne	Lms_ok
	mov	x11, #1000
	mul	x11, x20, x11
	ldr	w10, [x19, #TR_TS]
	add	x11, x11, x10             ; rounded up (and so never 0): the clock at or past it
	sdiv	x11, x11, x10
	ldr	x10, [x27, #E_FIRSTMS]
	sub	x12, x10, #1
	cmp	x11, x12
	csel	x11, x11, x10, ls         ; the smaller, 0 counting as none
	str	x11, [x27, #E_FIRSTMS]
	b	Lms_ok
Lms_trim:
	mov	x0, x23                   ; sound before it: decoded, cut
	mov	x1, x9
	mov	x2, x21
	bl	trim
Lms_ok:
	mov	x0, x23
	b	Lret3
Lms_none:
	mov	x0, #0
	b	Lret3

; pic_ref(sample) -> w0 = 0 for an H.264 or HEVC picture no other refers to (nal_ref_idc 0, or a sub-layer non-reference type), else 1 (x19 = track).
pic_ref:
	FRAME	1, 16
	mov	x20, x0
	ldr	x0, [x19, #TR_FD]
	bl	_CMFormatDescriptionGetMediaSubType
	lsr	w9, w0, #8
	mov	w10, #0x7663
	movk	w10, #0x61, lsl #16       ; 'avc'
	cmp	w9, w10
	cset	w19, eq                   ; 1: H.264
	mov	w10, #0x6331
	movk	w10, #0x6876, lsl #16     ; 'hvc1'
	cmp	w0, w10
	mov	w10, #0x7631
	movk	w10, #0x6865, lsl #16     ; 'hev1'
	ccmp	w0, w10, #4, ne
	mov	w9, #2
	csel	w19, w9, w19, eq          ; 2: HEVC
	mov	w0, #1
	cbz	w19, Lpr_end
	mov	x0, x20
	bl	_CMSampleBufferGetDataBuffer
	stp	xzr, xzr, [sp]
	mov	x1, #0
	mov	x2, sp
	mov	x3, #0
	add	x4, sp, #8
	bl	_CMBlockBufferGetDataPointer
	ldp	x9, x10, [sp]
	add	x9, x10, x9               ; the end
	mov	w0, #1
1:	add	x11, x10, #5              ; its first picture slice
	cmp	x11, x9
	b.hi	Lpr_end
	ldr	w11, [x10], #4
	rev	w11, w11
	ldrb	w12, [x10]
	add	x10, x10, x11
	cmp	w19, #1
	b.ne	2f
	and	w13, w12, #0x1f           ; H.264: slices are types 1-5
	sub	w13, w13, #1
	cmp	w13, #5
	b.hs	1b
	tst	w12, #0x60
	cset	w0, ne
	b	Lpr_end
2:	ubfx	w13, w12, #1, #6          ; HEVC: slices below 32; even ones below 16 are not referred to
	cmp	w13, #32
	b.hs	1b
	cmp	w13, #16
	and	w13, w13, #1
	ccmp	w13, #0, #0, lo
	cset	w0, ne
Lpr_end:
	ldr	x19, [x29, #-16]
	b	Lret1

; cur_sample(bb, base) -> the cursor's sample as a CMSampleBuffer over bb (holding the file from offset base), then the cursor moves on; 0 at the end (x19 = track).
cur_sample:
	FRAME	4
	mov	x25, x0
	mov	x26, x1
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	Lcp_none
	bl	cur_size
	mov	x20, x0
	bl	cur_delta
	mov	x21, x0
	bl	cur_cts
	mov	x22, x0
	bl	cur_sync
	mov	w23, w0
	ldr	x1, [x19, #TR_OFF]
	sub	x1, x1, x26
	mov	x0, x25
	mov	x2, x20
	ldr	x3, [x19, #TR_DTS]
	ldr	x9, [x19, #TR_SHIFT]
	sub	x3, x3, x9                ; decode time, after the edit
	add	x4, x3, x22
	mov	x5, x21
	mov	w6, w23
	bl	mk_sample
	mov	x20, x0
	bl	cur_step
	mov	x0, x20
	b	Lret4
Lcp_none:
	mov	x0, #0
	b	Lret4

; produce() -> the track's next sample (retained): from the mapped file, or from its stream's queue; 0 when there is none now (x19 = track).
produce:
	FRAME	1
	ldr	w9, [x19, #TR_SRC]
	cbnz	w9, Lpd_pop
Lpd_file:
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	Lpd_none
	bl	cur_size
	ldr	x9, [x19, #TR_OFF]
	add	x9, x9, x0
	ldr	x10, [x27, #E_LEN]
	cmp	x9, x10
	b.hi	Lpd_none                  ; outside the file
	ldr	x0, [x27, #E_PARENT]
	mov	x1, #0
	bl	cur_sample
	cbz	x0, Lpd_file              ; not decoded (before a seek's target): the next one
	b	Lret1
Lpd_pop:
	ldp	w9, w10, [x19, #TR_FH]
	cmp	w9, w10
	b.eq	Lpd_empty
	ldr	x11, [x19, #TR_FQ]
	and	w12, w9, #(FIFO_N - 1)
	ldr	x20, [x11, x12, lsl #3]
	add	w9, w9, #1
	str	w9, [x19, #TR_FH]
	ldr	x0, [x19, #TR_ST]
	bl	st_pump                   ; room again: maybe fetch on
	mov	x0, x20
	b	Lret1
Lpd_empty:
	ldr	x9, [x19, #TR_ST]
	ldr	x10, [x19, #TR_AFS]
	cmp	x9, #0
	ccmp	x10, #0, #4, eq
	b.eq	1f
	bl	afs_more                  ; a sound file: more of it read
	cbnz	w0, Lpd_pop
1:	mov	w9, #1
	str	w9, [x19, #TR_STARVE]     ; the next sample asks the renderer again
	ldr	x0, [x19, #TR_ST]
	bl	st_pump
Lpd_none:
	mov	x0, #0
	b	Lret1

; q_push(sample) — onto the track's queue; a renderer that ran dry asks again (x19 = track).
q_push:
	ldp	w9, w10, [x19, #TR_FH]
	sub	w11, w10, w9
	cmp	w11, #FIFO_N
	b.hs	_CFRelease                ; full: dropped (the fetching stops long before)
	ldr	x12, [x19, #TR_FQ]
	and	w13, w10, #(FIFO_N - 1)
	str	x0, [x12, x13, lsl #3]
	add	w10, w10, #1
	str	w10, [x19, #TR_FT]
	ldr	w9, [x19, #TR_STARVE]
	cbz	w9, 1f
	str	wzr, [x19, #TR_STARVE]
	b	trk_request
1:	ret

; q_clear — drop the track's queued samples and fragment list (x19 = track).
q_clear:
	FRAME	1
Lqc_next:
	ldp	w9, w10, [x19, #TR_FH]
	cmp	w9, w10
	b.eq	Lqc_done
	ldr	x11, [x19, #TR_FQ]
	and	w12, w9, #(FIFO_N - 1)
	ldr	x0, [x11, x12, lsl #3]
	add	w9, w9, #1
	str	w9, [x19, #TR_FH]
	bl	_CFRelease
	b	Lqc_next
Lqc_done:
	stp	wzr, wzr, [x19, #TR_FN]   ; TR_FN, TR_FI
	mov	w9, #1
	str	w9, [x19, #TR_STARVE]
	b	Lret1

; trk_request — the track's renderer asks for samples again, if it is a playing track (x19 = track).
trk_request:
	ldr	x9, [x27, #E_VT]
	cmp	x9, x19
	b.ne	1f
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, 3f                    ; Audio Only decodes no picture
	ldr	x0, [x27, #E_VR]
	ADDR	x3, Lblk_v
	b	2f
1:	ldr	x9, [x27, #E_AT]
	cmp	x9, x19
	b.ne	3f
	ldr	x0, [x27, #E_AR]
	ADDR	x3, Lblk_a
2:	ldr	x2, [x28, #G_MEDIAQ]
	ldr	x1, [x27, #S_requestMediaDataWhenReadyOnQueue_usingBlock_]
	b	_objc_msgSend
3:	ret

; feed_v / feed_a — a renderer wants more of its track.
	ENTRY	feed_v
	ldr	x0, [x27, #E_VT]
	ldr	x1, [x27, #E_VR]
	b	feed
	ENTRY	feed_a
	ldr	x0, [x27, #E_AT]
	ldr	x1, [x27, #E_AR]
; feed(track, renderer) — enqueue samples while the renderer takes them; at the end it stops asking.
feed:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	cbz	x19, Lfe_stop
Lfe_more:
	mov	x0, x20
	SEND	S_isReadyForMoreMediaData
	cbz	w0, Lret2
	bl	produce
	cbz	x0, Lfe_stop
	mov	x21, x0
	mov	x2, x0
	mov	x0, x20
	SEND	S_enqueueSampleBuffer_
	mov	x0, x21
	bl	_CFRelease
	b	Lfe_more
Lfe_stop:
	mov	x0, x20
	SEND	S_stopRequestingMediaData
	b	Lret2

; trk_play(track, renderer, block, ms) — the renderer drops what it holds, and the track plays from that moment, decoded from the sync sample before it.
trk_play:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	mov	x22, x3
	mov	x0, x20
	SEND	S_stopRequestingMediaData
	mov	x0, x20
	SEND	S_flush
	ldr	w9, [x19, #TR_TS]
	mul	x0, x22, x9
	mov	x9, #1000
	udiv	x0, x0, x9                ; the moment, in track units
	str	x0, [x19, #TR_TGT]
	ldr	x9, [x19, #TR_SHIFT]
	add	x0, x0, x9                ; and in the media's own time
	ldr	w9, [x19, #TR_KIND]
	mov	w1, #1
	cmp	w9, #'a'
	b.ne	1f
	mov	w1, #(1 + AUDIO_PREROLL)
	ldr	x9, [x19, #TR_AFS]
	cbz	x9, 1f
	mov	x0, x22                   ; a sound file
	bl	afs_seek
	b	2f
1:	bl	cur_seek
2:	mov	x0, x20
	ldr	x2, [x28, #G_MEDIAQ]
	mov	x3, x21
	SEND	S_requestMediaDataWhenReadyOnQueue_usingBlock_
	b	Lret2

; eng_seek(ms) — show that moment exactly: the clock holds there until its picture is ready, then goes on as before.
	ENTRY	eng_seek
	FRAME	1
	mov	x19, x0
	str	x19, [x27, #E_TGTMS]
	str	xzr, [x27, #E_FIRSTMS]
	ldr	w9, [x27, #E_NET]
	cbnz	w9, Lsq_net
	ldr	x9, [x27, #E_VT]
	ldr	x10, [x27, #E_AT]
	orr	x9, x9, x10
	cbz	x9, Lret1                 ; nothing open
	mov	x0, x19
	bl	hold
	ldr	x0, [x27, #E_VT]
	cbz	x0, Lsq_sound
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, Lsq_sound             ; Audio Only: no picture is decoded
	ldr	x1, [x27, #E_VR]
	ADDR	x2, Lblk_v
	mov	x3, x19
	bl	trk_play
Lsq_sound:
	ldr	x0, [x27, #E_AT]
	cbz	x0, Lsq_wait
	ldr	x1, [x27, #E_AR]
	ADDR	x2, Lblk_a
	mov	x3, x19
	bl	trk_play
Lsq_wait:
	mov	x0, x19
	bl	sub_seek
	bl	await
	b	Lret1
Lsq_net:
	mov	x0, x19
	bl	hold
	ldr	x0, [x27, #E_VR]          ; streams: both renderers drop what they hold, each stream seeks
	SEND	S_stopRequestingMediaData
	ldr	x0, [x27, #E_VR]
	SEND	S_flush
	ldr	x0, [x27, #E_AR]
	SEND	S_stopRequestingMediaData
	ldr	x0, [x27, #E_AR]
	SEND	S_flush
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, 1f                    ; Audio Only: the picture's stream stays still
	BADDR	x0, E_ST
	mov	x1, x19
	bl	st_seek
1:	BADDR	x0, (E_ST + ST_SIZE)
	mov	x1, x19
	bl	st_seek
	BADDR	x0, (E_ST + 2 * ST_SIZE)
	mov	x1, x19
	bl	st_seek
	b	Lsq_wait

; hold(ms) — the clock stops at that moment until await lets it go.
hold:
	FRAME	0, 32
	mov	w9, #1
	str	w9, [x27, #E_HOLD]
	mov	x9, #1000
	orr	x9, x9, #(1 << 32)
	stp	x0, x9, [sp]              ; CMTime in milliseconds
	str	xzr, [sp, #16]
	ldr	x0, [x27, #E_SYNC]
	movi	d0, #0
	mov	x2, sp
	SEND	S_setRate_time_
	b	Lret0

; await — wait for the first picture, then the clock may run.
await:
	mov	w9, #WAIT_TRIES
	str	w9, [x27, #E_WAITN]
	ldr	w0, [x27, #E_WAITGEN]
	add	w0, w0, #1
	str	w0, [x27, #E_WAITGEN]
	b	Leng_wait

; eng_seekq — the newest seek the main thread queued.
	ENTRY	eng_seekq
	add	x9, x28, #G_SEEKPEND
	swpal	wzr, w10, [x9]
	ldr	x0, [x28, #G_SEEKTO]
	b	Leng_seek

; eng_wait(generation) — every 5 ms until the picture at the seek is ready (or a second passed): then the clock may run.
	ENTRY	eng_wait
	FRAME	0
	ldr	w9, [x27, #E_WAITGEN]
	cmp	w0, w9
	b.ne	Lret0                     ; a newer seek waits instead
	ldr	w9, [x27, #E_WANTV]
	cbz	w9, Lew_go
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, Lew_go
	ldr	w9, [x27, #E_WAITN]
	subs	w9, w9, #1
	b.lo	Lew_go
	str	w9, [x27, #E_WAITN]
	ldr	x0, [x28, #G_SBLAYER]
	SEND	S_isReadyForDisplay
	cbnz	w0, Lew_go
	cmp	w9, #(WAIT_TRIES - 40)
	b.hi	1f                        ; a moment for every picture of the first segment to come
	ldr	x0, [x27, #E_FIRSTMS]     ; the earliest picture comes after the target (HLS segments): the clock holds at it
	ldr	x9, [x27, #E_TGTMS]
	cmp	x0, x9
	b.le	1f
	str	x0, [x27, #E_TGTMS]
	bl	hold
1:
	mov	x0, #0                    ; DISPATCH_TIME_NOW
	mov	w1, #(WAIT_NS & 0xffff)
	movk	w1, #(WAIT_NS >> 16), lsl #16
	bl	_dispatch_time
	ldr	x1, [x28, #G_MEDIAQ]
	ldr	w2, [x27, #E_WAITGEN]
	adr	x3, eng_wait
	bl	_dispatch_after_f
	b	Lret0
Lew_go:
	str	wzr, [x27, #E_HOLD]
	bl	Leng_rate
	b	Lret0

; eng_rate — the clock runs at the chosen speed while playing, else holds; not while a seek waits for its picture.
	ENTRY	eng_rate
	ldr	w9, [x27, #E_HOLD]
	cbnz	w9, 1f
	ldr	x0, [x27, #E_SYNC]
	ldr	s0, [x28, #G_RATE]
	movi	d1, #0
	ldr	w9, [x28, #G_PLAYING]
	cmp	w9, #0
	fcsel	s0, s0, s1, ne
	SENDT	S_setRate_
1:	ret

; now_ms -> x0 = the clock, ms.
now_ms:
	FRAME	0, 32
	stp	xzr, xzr, [sp]            ; 0 before the synchronizer exists
	ldr	x0, [x27, #E_SYNC]
	mov	x8, sp
	SEND	S_currentTime
	ldr	x9, [sp]
	ldrsw	x10, [sp, #8]
	mov	x11, #1000
	mul	x9, x9, x11
	sdiv	x0, x9, x10
	b	Lret0

; sub_tick(block, time) — the clock moved: the subtitle track's cues up to now are shown in turn, the last one until it ends.
	ENTRY	sub_tick
	FRAME	2, 32
	ldr	x19, [x27, #E_SUBT]
	cbz	x19, Lret2
	ldr	x9, [x1]                  ; now, in the track's units
	ldr	w10, [x1, #8]
	ldr	w11, [x19, #TR_TS]
	mul	x9, x9, x11
	sdiv	x20, x9, x10
Lsb_next:
	ldr	x0, [x27, #E_SUBN]
	cbnz	x0, 1f
	bl	produce
	cbz	x0, Lsb_end
	str	x0, [x27, #E_SUBN]
1:	mov	x8, sp
	bl	_CMSampleBufferGetPresentationTimeStamp
	ldr	x21, [sp]
	cmp	x21, x20
	b.gt	Lsb_end                   ; not yet
	ldr	x0, [x27, #E_SUBN]
	mov	x8, sp
	bl	_CMSampleBufferGetDuration
	ldr	x9, [sp]
	add	x9, x21, x9
	str	x9, [x27, #E_SUBEND]
	ldr	x0, [x27, #E_SUBN]
	str	xzr, [x27, #E_SUBN]
	bl	sub_cue
	b	Lsb_next
Lsb_end:
	ldr	w9, [x27, #E_SUBON]
	cbz	w9, Lret2
	ldr	x10, [x27, #E_SUBEND]
	cmp	x20, x10
	b.lt	Lret2
	mov	x0, #0                    ; it ended
	bl	sub_text
	b	Lret2

; sub_cue(sample) — the cue's text, from its format: tx3g or QuickTime text (a length, then UTF-8), or WebVTT boxes; the sample is released.
sub_cue:
	FRAME	3, 32
	mov	x19, x0
	bl	_CMSampleBufferGetFormatDescription
	bl	_CMFormatDescriptionGetMediaSubType
	mov	w20, w0
	mov	x0, x19
	bl	_CMSampleBufferGetDataBuffer
	stp	xzr, xzr, [sp]
	mov	x1, #0
	mov	x2, #0
	mov	x3, sp
	add	x4, sp, #8
	bl	_CMBlockBufferGetDataPointer
	ldp	x22, x21, [sp]            ; length, bytes (0 without data)
	add	x22, x21, x22             ; the end
	TYPE	w9, 't','t','v','w'      ; 'wvtt'
	cmp	w20, w9
	b.eq	Lsu_vtt
	TYPE	w9, '8','0','6','c'      ; 'c608': field 1's byte pairs for the decoder, which keeps the caption shown
	cmp	w20, w9
	b.eq	Lsu_608
	add	x0, x21, #2               ; a length, then the text
	cmp	x0, x22
	b.hi	Lsu_none
	ldrh	w9, [x21]
	rev16	w9, w9
	add	x1, x0, x9
	cmp	x1, x22
	csel	x1, x1, x22, ls
	b	Lsu_show
Lsu_vtt:
	mov	x0, x21                   ; the cue box's payload box
	mov	x1, x22
	TYPE	w2, 'v','t','t','c'
	bl	box_find
	cbz	x0, Lsu_none              ; vtte: no cue
	TYPE	w2, 'p','a','y','l'
	bl	box_find
	cbnz	x0, Lsu_show
Lsu_none:
	mov	x0, #0
	mov	x1, #0
Lsu_show:
	sub	x1, x1, x0
	bl	sub_textn
Lsu_done:
	mov	x0, x19
	bl	_CFRelease
	b	Lret3
Lsu_608:
	mov	x0, x21
	mov	x1, x22
	TYPE	w2, 'c','d','a','t'
	bl	box_find
	cbz	x0, Lsu_done
	mov	x21, x0
	mov	x22, x1
	mov	x23, x19
	BADDR	x19, E_CC
1:	add	x9, x21, #2
	cmp	x9, x22
	b.hi	2f
	ldrb	w0, [x21], #1
	ldrb	w1, [x21], #1
	bl	cc_pair
	b	1b
2:	add	x0, x19, #(CC_D + 4)
	ldr	w1, [x19, #CC_D]
	mov	x19, x23
	b	Lsu_show

; sub_textn(bytes, length) — show that cue text: tags dropped, &amp; &lt; &gt; decoded; nothing clears it.
sub_textn:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	x0, #0
	cbz	x20, 1f
	add	x0, x20, #1
	bl	_malloc
	cbz	x0, Lret2
	mov	x21, x0
	mov	x9, x19
	add	x10, x19, x20
	mov	x11, x0
	mov	w12, #0                   ; inside a tag
Ltn_ch:
	cmp	x9, x10
	b.hs	Ltn_end
	ldrb	w13, [x9], #1
	cmp	w13, #'<'
	csinc	w12, w12, wzr, ne
	cbnz	w12, Ltn_tag
	cmp	w13, #'&'
	b.ne	Ltn_put
	sub	x14, x10, x9
	cmp	x14, #3
	b.lo	Ltn_put
	ldrh	w14, [x9]
	ldrb	w15, [x9, #2]
	TYPE	w16, 'l','t',0,0
	mov	w17, #'<'
	cmp	w14, w16
	b.eq	Ltn_ent
	TYPE	w16, 'g','t',0,0
	mov	w17, #'>'
	cmp	w14, w16
	b.eq	Ltn_ent
	TYPE	w16, 'a','m',0,0
	cmp	w14, w16
	b.ne	Ltn_put
	cmp	w15, #'p'
	b.ne	Ltn_put
	sub	x14, x10, x9
	cmp	x14, #4
	b.lo	Ltn_put
	ldrb	w15, [x9, #3]             ; &amp;
	cmp	w15, #';'
	b.ne	Ltn_put
	add	x9, x9, #4
	b	Ltn_put
Ltn_ent:
	cmp	w15, #';'                 ; &lt; &gt;
	b.ne	Ltn_put
	add	x9, x9, #3
	mov	w13, w17
Ltn_put:
	strb	w13, [x11], #1
	b	Ltn_ch
Ltn_tag:
	cmp	w13, #'>'
	csel	w12, wzr, w12, eq
	b	Ltn_ch
Ltn_end:
	strb	wzr, [x11]
	mov	x0, x21
	bl	mkstr
	SEND	S_retain                  ; main has it next
	mov	x20, x0
	mov	x0, x21
	bl	_free
	mov	x0, x20
1:	bl	sub_text
	b	Lret2

; sub_text(text) — main shows that NSString (released there), or clears with 0.
sub_text:
	cmp	x0, #0
	cset	w9, ne
	str	w9, [x27, #E_SUBON]
	mov	x1, x0
	adr	x0, sub_show
	b	post_main

; sub_reset — no cue shown or waiting, no caption decoded: another moment or track.
sub_reset:
	FRAME	0
	BADDR	x0, E_CC
	mov	x1, #CC_SIZE
	bl	_bzero
	ldr	x0, [x27, #E_SUBN]
	str	xzr, [x27, #E_SUBN]
	cbz	x0, 1f
	bl	_CFRelease
1:	str	xzr, [x27, #E_SUBEND]
	ldr	w9, [x27, #E_SUBON]
	cbz	w9, Lret0
	mov	x0, #0
	bl	sub_text
	b	Lret0

; sub_seek(ms) — the subtitles start again at that moment; a stream's track starts with its stream.
sub_seek:
	FRAME	1
	mov	x20, x0
	bl	sub_reset
	ldr	x19, [x27, #E_CCT]        ; the captions' cues come again with the picture
	cbz	x19, 1f
	bl	q_clear
1:	ldr	x0, [x27, #E_SUBT]
	cbz	x0, Lret1
	ldr	w9, [x0, #TR_SRC]
	cbnz	w9, Lret1
	mov	x1, #0                    ; no renderer
	mov	x2, #0
	mov	x3, x20
	bl	trk_play
	b	Lret1

; sub_show(text) — the subtitle layer over the picture shows the text (released), centered near the bottom; 0 clears it.
	ENTRY	sub_show
	FRAME	2, 48
	mov	x19, x0
	ldr	x20, [x27, #B_SUBL]
	cbnz	x20, 1f
	CLASS	x0, CATextLayer
	SEND	S_new
	mov	x20, x0
	str	x0, [x27, #B_SUBL]
	CSTR	x0, "center"
	bl	mkstr
	mov	x2, x0
	mov	x0, x20
	SEND	S_setAlignmentMode_
	ldr	x0, [x28, #G_WIN]
	SEND	S_backingScaleFactor
	mov	x0, x20
	SEND	S_setContentsScale_       ; sharp on Retina
	mov	x0, x20
	fmov	s0, #1.0
	SEND	S_setShadowOpacity_
	CLASS	x0, NSFont
	movi	d0, #0
	ldr	x9, [x27, #F_NSFontWeightSemibold]
	ldr	d1, [x9]
	SEND	S_systemFontOfSize_weight_
	mov	x2, x0
	mov	x0, x20
	SEND	S_setFont_
	ldr	x0, [x28, #G_SBV]         ; beside the picture, not turned with it
	SEND	S_layer
	mov	x2, x20
	SEND	S_addSublayer_
1:	CLASS	x0, CATransaction         ; at once, not faded in
	SEND	S_begin
	CLASS	x0, CATransaction
	mov	w2, #1
	SEND	S_setDisableActions_
	ldr	x0, [x28, #G_SBV]
	SEND	S_bounds
	stp	d2, d3, [sp]              ; the view's width and height
	fmov	d0, #0.125
	fmul	d0, d3, d0
	fmov	d1, #0.375
	fmul	d0, d0, d1                ; the text: about 1/20 of the picture's height
	str	d0, [sp, #32]
	mov	x0, x20
	SEND	S_setFontSize_
	mov	x0, x20
	mov	w2, #0                    ; measured on its own lines (wrapped, it measures stale)
	SEND	S_setWrapped_
	mov	x0, x20
	mov	x2, x19
	SEND	S_setString_
	mov	x0, x20
	SEND	S_preferredFrameSize      ; d0, d1: its size
	ldp	d2, d3, [sp]
	fmov	d4, #0.875
	fmul	d4, d2, d4                ; the widest it goes
	fcmp	d0, d4
	b.le	2f
	fdiv	d5, d0, d4                ; wider: wrapped into more lines
	frintp	d5, d5
	fmul	d1, d1, d5
	fmov	d0, d4
	stp	d0, d1, [sp, #16]
	mov	x0, x20
	mov	w2, #1
	SEND	S_setWrapped_
	ldp	d0, d1, [sp, #16]
	ldp	d2, d3, [sp]
2:	fsub	d4, d2, d0
	fmov	d5, #0.5
	fmul	d4, d4, d5                ; centered
	ldr	d5, [sp, #32]             ; a line above the bottom edge
	fmov	d2, d0
	fmov	d3, d1
	fmov	d0, d4
	fmov	d1, d5
	mov	x0, x20
	SEND	S_setFrame_
	CLASS	x0, CATransaction
	SEND	S_commit
	mov	x0, x19
	SEND	S_release
	b	Lret2

; eng_vol — the sound renderer takes G's volume and mute.
	ENTRY	eng_vol
	FRAME	0
	ldr	x0, [x27, #E_AR]
	ldr	w9, [x28, #G_VOLPCT]
	scvtf	s0, w9
	ldr	s1, [x28, #(Lf_100 - G)]
	fdiv	s0, s0, s1
	SEND	S_setVolume_
	ldr	x0, [x27, #E_AR]
	ldr	w2, [x28, #G_MUTED]
	SEND	S_setMuted_
	b	Lret0

; eng_aonly — Audio Only: the picture stops being decoded, or comes back a moment ahead, decoded from its sync sample.
	ENTRY	eng_aonly
	FRAME	1, 32
	ldr	w9, [x27, #E_NET]
	cbnz	w9, Lea_net
	ldr	x0, [x27, #E_VT]
	cbz	x0, Lret1
	ldr	w9, [x28, #G_AONLY]
	cbz	w9, Lea_back
	ldr	x0, [x27, #E_VR]
	SEND	S_stopRequestingMediaData
	ldr	x0, [x27, #E_VR]
	mov	w2, #1
	mov	x3, #0
	SEND	S_flushWithRemovalOfDisplayedImage_completionHandler_
	b	Lret1
Lea_back:
	bl	now_ms
	add	x3, x0, #300              ; 0.3 s ahead, while it decodes
	ldr	x0, [x27, #E_VT]
	ldr	x1, [x27, #E_VR]
	ADDR	x2, Lblk_v
	bl	trk_play
	b	Lret1
Lea_net:
	ldr	w9, [x27, #E_LIVE]
	cbz	w9, Lea_vod
	mov	x0, #32                   ; a broadcast: opened again with the other stream
	bl	_malloc
	cbz	x0, Lret1
	mov	x19, x0
	ldr	w9, [x27, #E_GEN]
	mov	w10, #1
	stp	w9, w10, [x19, #YT_GEN]
	str	xzr, [x19, #YT_DUR]
	ldr	x0, [x27, #(E_ST + ST_URL)]
	bl	_strdup
	str	x0, [x19, #YT_V]
	ldr	x0, [x27, #(E_ST + ST_SIZE + ST_URL)]
	bl	_strdup
	str	x0, [x19, #YT_A]
	mov	x0, x19
	bl	Leng_tube
	b	Lret1
Lea_vod:
	ldr	x0, [x27, #E_VR]          ; streams: the picture's stream stops, or starts again just ahead
	SEND	S_stopRequestingMediaData
	ldr	x0, [x27, #E_VR]
	mov	w2, #1
	mov	x3, #0
	SEND	S_flushWithRemovalOfDisplayedImage_completionHandler_
	ldr	x9, [x27, #(E_ST + ST_SIZE + ST_URL)]
	ldr	x10, [x27, #(E_ST + ST_SIZE + ST_PLURL)]
	orr	x9, x9, x10
	ldr	w10, [x28, #G_AONLY]
	cbz	w10, 1f
	ldr	x19, [x27, #E_VT]         ; on: what is queued goes; YouTube's picture stream stops (one stream for both goes on, its pictures dropped)
	cbz	x19, 2f
	bl	q_clear
2:	cbz	x9, Lret1
	BADDR	x0, E_ST
	bl	st_reset
	b	Lret1
1:	mov	x19, x9
	bl	now_ms
	mov	x1, x0
	cbz	x19, 3f                   ; off, one stream for both: everything restarts from now
	add	x1, x1, #1000             ; YouTube: its picture stream from a second ahead, fetched and decoded meanwhile
	BADDR	x0, E_ST
	bl	st_seek
	b	Lret1
3:	mov	x0, x1
	bl	Leng_seek
	b	Lret1

; net_tick(generation) — every quarter second while streams play: a track running dry holds the clock until STALL_FULL ms are in again.
	ENTRY	net_tick
	FRAME	2, 32
	mov	w19, w0
	ldr	w9, [x27, #E_GEN]
	ldr	w10, [x27, #E_NET]
	cmp	w0, w9
	ccmp	w10, #0, #4, eq
	b.eq	Lret2                     ; other media now: no more ticks
	bl	now_ms
	mov	x20, x0                   ; the clock, ms
	mov	x21, #0x7fffffffffffffff
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, 1f
	ldr	x0, [x27, #E_VT]
	bl	ahead_ms
	cmp	x0, x21
	csel	x21, x0, x21, lt
1:	ldr	x0, [x27, #E_AT]
	bl	ahead_ms
	cmp	x0, x21
	csel	x21, x0, x21, lt          ; the least time queued ahead
	ldr	w9, [x27, #E_HOLD]
	tbnz	w9, #1, Lnt_dry
	ldr	w10, [x28, #G_PLAYING]
	cmp	w9, #0
	ccmp	w10, #0, #4, eq
	b.eq	Lnt_again                 ; paused, or a seek waits
	cmp	x21, #STALL_LOW
	b.ge	Lnt_again
	orr	w9, w9, #2                ; dry: the clock holds
	str	w9, [x27, #E_HOLD]
	ldr	x0, [x27, #E_SYNC]
	movi	d0, #0
	SEND	S_setRate_
	b	Lnt_again
Lnt_dry:
	cmp	x21, #STALL_FULL
	b.lt	Lnt_again
	and	w9, w9, #~2
	str	w9, [x27, #E_HOLD]
	bl	Leng_rate
Lnt_again:
	mov	w0, w19
	bl	tick_later
	b	Lret2

; tick_later(generation) — net_tick in a quarter second.
tick_later:
	FRAME	1
	mov	w19, w0
	mov	x0, #0
	mov	w1, #(TICK_NS & 0xffff)
	movk	w1, #(TICK_NS >> 16), lsl #16
	bl	_dispatch_time
	ldr	x1, [x28, #G_MEDIAQ]
	mov	w2, w19
	adr	x3, net_tick
	bl	_dispatch_after_f
	b	Lret1

; ahead_ms(track) -> x0 = ms of it queued past the clock (x20, ms); a large number with nothing more to come.
ahead_ms:
	mov	x9, #0x7fffffffffffffff
	cbz	x0, 1f
	ldr	x10, [x0, #TR_ST]
	cbz	x10, 1f
	ldr	w11, [x10, #ST_EOS]
	cbnz	w11, 1f
	ldr	x10, [x0, #TR_LAST]
	mov	x11, #1000
	mul	x10, x10, x11
	ldr	w11, [x0, #TR_TS]
	sdiv	x10, x10, x11
	sub	x9, x10, x20
1:	mov	x0, x9
	ret

; eng_tube(request) — YouTube on This Mac: its picture and sound streams; request = {generation, live, ms, picture URL, sound URL}, freed here (URLs become the streams').
	ENTRY	eng_tube
	FRAME	1
	mov	x19, x0
	bl	Leng_close
	mov	x9, #-1
	str	x9, [x27, #E_T0]
	mov	x0, #0
	bl	hold
	ldp	w9, w10, [x19, #YT_GEN]
	str	w9, [x27, #E_GEN]
	ldr	x9, [x19, #YT_DUR]
	str	x9, [x27, #E_DURMS]
	mov	w9, #1
	str	w9, [x27, #E_NET]
	str	w9, [x27, #E_ISO]
	ldr	w20, [x19, #YT_LIVE]
	str	w20, [x27, #E_LIVE]
	ldr	w21, [x28, #G_AONLY]
	ldr	x1, [x19, #YT_V]
	cbz	x1, 2f
	eor	w9, w21, #1
	str	w9, [x27, #E_WANTV]
	BADDR	x0, E_ST
	cbnz	w9, 1f
	str	x1, [x0, #ST_URL]         ; Audio Only: kept for later
	b	2f
1:	mov	w2, #0
	bl	st_open
	cbz	w20, 2f
	ldr	x0, [x19, #YT_A]          ; a broadcast's picture is its HLS, sound in it: the DASH sound is kept for Audio Only
	str	x0, [x27, #(E_ST + ST_SIZE + ST_URL)]
	b	3f
2:	BADDR	x0, (E_ST + ST_SIZE)
	ldr	x1, [x19, #YT_A]
	mov	w2, w20
	bl	st_open
3:
	mov	x0, x19
	bl	_free
	bl	await                     ; the clock held at 0 until the picture is ready
	ldr	w0, [x27, #E_GEN]
	bl	tick_later
	adr	x0, ui_poll
	mov	x1, #0
	bl	post_main
	b	Lret1

; eng_web(request) — any other web address on This Mac: one stream, its tracks as its movie box lists them; request = {generation, URL} like eng_open's.
	ENTRY	eng_web
	FRAME	1
	mov	x19, x0
	bl	Leng_close
	mov	x9, #-1                   ; HLS: the timeline is anchored at the first time stamp
	str	x9, [x27, #E_T0]
	mov	x0, #0
	bl	hold
	ldr	w9, [x19]
	str	w9, [x27, #E_GEN]
	mov	w9, #1
	str	w9, [x27, #E_NET]
	str	w9, [x27, #E_ISO]
	str	w9, [x27, #E_WANTV]       ; until its tracks say otherwise
	add	x0, x19, #8
	bl	_strdup
	mov	x20, x0
	mov	x0, x19
	bl	_free
	cbz	x20, Lret1
	BADDR	x0, E_ST
	mov	x1, x20
	mov	w2, #0
	bl	st_open
	bl	await
	ldr	w0, [x27, #E_GEN]
	bl	tick_later
	adr	x0, ui_poll
	mov	x1, #0
	bl	post_main
	b	Lret1

; ---- Actions (Objective-C methods: self, _cmd, sender) ----

; act_toggle — the play/pause button and Space.
	ENTRY	act_toggle
	b	local_toggle

; act_stop — Cmd-.
	ENTRY	act_stop
	b	local_stop

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
	mov	x9, #1000
	mul	x0, x19, x9
	bl	seek_route
	b	Lret2

; seek_route(ms) — hold polled positions for the seek, then send it.
seek_route:
	ldr	x9, [x28, #G_TICK]
	add	x9, x9, #HOLD_TICKS
	str	x9, [x28, #G_SEEKH]
	b	local_seekms

; act_volup / act_voldown — Cmd-Up / Cmd-Down: one volume step.
	ENTRY	act_volup
	mov	w0, #VOLUME_STEP
	b	local_volstep
	ENTRY	act_voldown
	mov	w0, #-VOLUME_STEP
	b	local_volstep

; act_mute — the mute button and Opt-Cmd-Down.
	ENTRY	act_mute
	b	local_mute

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

; play_text(text) — resolve and play a link, search, web address or file path (copied); the newest one wins.
play_text:
	FRAME	2
	mov	x19, x0
	ldrb	w9, [x19]
	cbz	w9, Lret2                 ; empty
	mov	x0, #1
	mov	x1, #JOB_SIZE
	bl	_calloc
	cbz	x0, Lret2
	mov	x20, x0
	mov	x0, x19
	bl	_strdup                   ; the caller's text dies with its pool
	str	x0, [x20, #JOB_QUERY]
	cbz	x0, Lpt_drop
	ldr	w9, [x28, #G_PLAYGEN]
	add	w9, w9, #1
	str	w9, [x28, #G_PLAYGEN]
	str	w9, [x20, #JOB_GEN]
	mov	w9, #1
	str	w9, [x28, #G_LOADING]
	ADDR	x0, Lprog_busy
	bl	ui_run
	GADDR	x0, Ls_slash+1
	mov	w1, #0
	bl	set_status
	bl	stage_update
	ldr	x0, [x20, #JOB_QUERY]     ; a file needs no lookup: resolved here, at once
	ldrb	w9, [x0]
	cmp	w9, #'/'
	b.eq	1f
	CSTR	x1, "file://"
	mov	x2, #7
	bl	_strncmp
	cbnz	w0, 2f
1:	mov	x0, x20
	bl	Lplay_resolve
	b	Lret2
2:	WORKQ
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
	adr	x0, eng_aonly
	mov	x1, #0
	bl	eng_cmd
	bl	local_poll
	b	Lret1

; act_vol — the volume slider.
	ENTRY	act_vol
	FRAME	1
	ldr	x0, [x28, #G_VOL]
	SEND	S_intValue
	mov	w19, w0
	bl	dragging
	str	w0, [x28, #G_VOLDRAG]
	ldr	x9, [x28, #G_TICK]
	add	x9, x9, #HOLD_TICKS
	str	x9, [x28, #G_VOLH]
	mov	w0, w19
	bl	local_setvol
	b	Lret1

; act_seek — the position slider: This Mac follows the drag frame by frame.
	ENTRY	act_seek
	FRAME	1
	ldr	x0, [x28, #G_POS]
	SEND	S_doubleValue
	mov	x9, #1000
	scvtf	d1, x9
	fmul	d0, d0, d1
	fcvtzs	x19, d0                   ; to the millisecond
	ldr	x0, [x28, #G_POS]
	SEND	S_maxValue
	fcvtzs	x1, d0
	mov	x9, #1000
	sdiv	x0, x19, x9
	bl	show_time
	bl	dragging
	str	w0, [x28, #G_SEEKDRAG]
	cbz	w0, Lsk_release
	mov	x0, x19
	bl	local_seekms
	b	Lret1
Lsk_release:
	mov	x0, x19
	bl	seek_route
	b	Lret1

; act_tick — the 1 Hz timer: the controls' idle fade; This Mac renders itself.
	ENTRY	act_tick
	FRAME	0
	ldr	x10, [x28, #G_TICK]
	add	x10, x10, #1
	str	x10, [x28, #G_TICK]
	bl	idle_tick
	bl	local_poll
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
	tbnz	x0, #14, Lak_full
	b	Lret0                     ; not full screen
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
	adr	x0, eng_rate
	mov	x1, #0
	bl	eng_cmd
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

; act_options(menu) — View > Subtitles and Audio Track as they open: the tracks, the chosen one checked.
	ENTRY	act_options
	FRAME	4
	mov	x19, x2
	mov	x0, x19
	SEND	S_removeAllItems
	ldr	w9, [x28, #G_MODE]
	cbnz	w9, Lop_av
	ldr	x0, [x28, #G_MEDIAQ]      ; the engine's own, read while its queue waits
	mov	x1, x19
	adr	x2, eng_options
	bl	_dispatch_sync_f
	b	Lret4
Lop_av:
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
	mov	x2, #-1
	cmp	x22, #0
	cset	w3, eq
	bl	opt_item
	cbz	x20, Lop_list
	mov	w2, #0                    ; with one sound track there is nothing to choose
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
	mov	x2, x26
	cmp	x20, x22
	cset	w3, eq
	bl	opt_item
	add	x26, x26, #1
	b	Lop_each

; opt_item(menu, title, tag, on) -> x0 = an option for act_option, checked when on.
opt_item:
	FRAME	2
	mov	x19, x2
	mov	w20, w3
	ldr	x2, [x27, #S_act_option_]
	GADDR	x3, Ls_slash+1            ; no key
	bl	add_item
	mov	x21, x0
	mov	x2, x19
	SEND	S_setTag_
	mov	x0, x21
	mov	w2, w20
	SEND	S_setState_
	mov	x0, x21
	b	Lret2

; eng_options(menu) — the engine's subtitle or sound tracks as options, named by language (on main, the media queue waiting).
	ENTRY	eng_options
	FRAME	4, 96
	mov	x19, x0
	ldr	x9, [x28, #G_SUBMENU]
	cmp	x19, x9
	ldr	x20, [x27, #E_SUBT]
	ldr	x9, [x27, #E_AT]
	csel	x20, x20, x9, eq          ; the one playing
	mov	w21, #'s'
	mov	w9, #'a'
	csel	w21, w21, w9, eq          ; the kind listed
	b.ne	1f
	mov	x0, x19                   ; subtitles can be off
	CSTR	x1, "Off"
	mov	x2, #-1
	cmp	x20, #0
	cset	w3, eq
	bl	opt_item
1:	ldr	x9, [x27, #E_MASTER]
	cbnz	x9, Leo_hls
	BADDR	x22, E_TR
	mov	w23, #0                   ; the track
	mov	w24, #0                   ; its number in the list
Leo_each:
	ldr	w9, [x27, #E_NTR]
	cmp	w23, w9
	b.hs	Lret4
	ldr	w9, [x22, #TR_KIND]
	cmp	w9, w21
	b.ne	Leo_next
	add	w24, w24, #1
	ldr	w9, [x22, #TR_LANG]
	str	w9, [sp, #8]              ; three letters and a NUL
	cbz	w9, 2f
	add	x0, sp, #8
	bl	mkstr
	mov	x25, x0
	CLASS	x0, NSLocale
	SEND	S_currentLocale
	mov	x2, x25
	SEND	S_localizedStringForLanguageCode_
	cbz	x0, 2f
	SEND	S_UTF8String
	mov	x1, x0
	b	3f
2:	str	x24, [sp]                 ; no language: its number
	add	x0, sp, #16
	mov	x1, #16
	CSTR	x2, "Track %d"
	bl	_snprintf
	add	x1, sp, #16
3:	mov	x0, x19
	mov	w2, w23
	cmp	x22, x20
	cset	w3, eq
	bl	opt_item
Leo_next:
	add	x22, x22, #TR_SIZE
	add	w23, w23, #1
	b	Leo_each
Leo_hls:
	BADDR	x24, (E_ST + ST_SIZE)     ; HLS: the master's renditions, by NAME; the one its stream plays checked
	CSTR	x25, "TYPE=AUDIO"
	cmp	w21, #'s'
	b.ne	1f
	add	x24, x24, #ST_SIZE
	CSTR	x25, "TYPE=SUBTITLES"
1:	ldr	x24, [x24, #ST_PLURL]
	mov	x26, #0                   ; sound: the playing one's group, for its siblings
	cmp	w21, #'s'
	b.eq	Leo_list
	ldr	x22, [x27, #E_MASTER]
2:	mov	x0, x22
	mov	x1, x25
	bl	media_next
	cbz	x0, Lret4                 ; none playing: nothing to choose
	mov	x22, x2
	stp	x0, x1, [sp]
	mov	x3, x24
	bl	uri_is
	cbz	w0, 2b
	ldp	x0, x1, [sp]
	CSTR	x2, "GROUP-ID="
	bl	attr
	mov	x26, x0
	stp	x0, x1, [sp, #16]         ; its group
Leo_list:
	ldr	x22, [x27, #E_MASTER]
	mov	w23, #0x1000              ; the rendition's tag: 0x1000 + its index
Leo_rend:
	mov	x0, x22
	mov	x1, x25
	bl	media_next
	cbz	x0, Leo_cc
	mov	x22, x2
	stp	x0, x1, [sp]              ; the line
	cbz	x26, 3f
	CSTR	x2, "GROUP-ID="
	bl	attr
	cbz	x0, Leo_skip
	ldp	x9, x10, [sp, #16]
	sub	x2, x10, x9
	sub	x11, x1, x0
	cmp	x11, x2
	b.ne	Leo_skip
	mov	x1, x9
	bl	_strncmp
	cbnz	w0, Leo_skip
3:	ldp	x0, x1, [sp]
	mov	x3, x24
	bl	uri_is
	mov	w4, w0
	ldp	x0, x1, [sp]
	mov	x2, x19
	mov	w3, w23
	bl	opt_named
Leo_skip:
	add	w23, w23, #1
	b	Leo_rend
Leo_cc:
	cmp	w21, #'s'                 ; subtitles: then the captions in the picture (CC1 only), tagged 0x2000 + their index
	b.ne	Lret4
	ldr	x22, [x27, #E_MASTER]
	mov	w23, #0x2000
1:	mov	x0, x22
	CSTR	x1, "TYPE=CLOSED-CAPTIONS"
	bl	media_next
	cbz	x0, Lret4
	mov	x22, x2
	stp	x0, x1, [sp]
	sub	x2, x1, x0
	CSTR	x1, "\"CC1\""
	bl	_strnstr
	cbz	x0, 2f
	ldr	x9, [x27, #E_CCT]
	ldr	x10, [x27, #E_SUBT]
	cmp	x9, #0
	ccmp	x9, x10, #0, ne
	cset	w4, eq
	ldp	x0, x1, [sp]
	mov	x2, x19
	mov	w3, w23
	bl	opt_named
2:	add	w23, w23, #1
	b	1b

; opt_named(line, end, menu, tag, on) — an option titled by the line's NAME (none: no option).
opt_named:
	FRAME	2, 48
	mov	x19, x2
	mov	w20, w3
	mov	w21, w4
	CSTR	x2, "NAME="
	bl	attr
	cbz	x0, Lret2
	sub	x2, x1, x0
	cmp	x2, #47
	mov	x9, #47
	csel	x2, x2, x9, lo
	mov	x1, x0
	mov	x0, sp
	strb	wzr, [x0, x2]
	bl	_memcpy
	mov	x0, x19
	mov	x1, sp
	mov	w2, w20
	mov	w3, w21
	bl	opt_item
	b	Lret2

; txt_fd(track) — the track's format: tx3g text cues.
txt_fd:
	add	x4, x0, #TR_FD
	mov	x0, #0
	mov	w1, #0x3367
	movk	w1, #0x7478, lsl #16
	mov	w2, w1
	mov	x3, #0
	b	_CMFormatDescriptionCreate

; cc_track -> x0 = the CC1 caption track, made once: fed from the picture's SEI, read from its queue.
cc_track:
	FRAME	1
	ldr	x0, [x27, #E_CCT]
	cbnz	x0, Lret1
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Lret1
	add	w10, w9, #1
	str	w10, [x27, #E_NTR]
	BADDR	x19, E_TR
	add	x19, x19, x9, lsl #9
	mov	w9, #'s'
	mov	w10, #(90000 & 0xffff)
	movk	w10, #(90000 >> 16), lsl #16
	stp	w9, w10, [x19, #TR_KIND]
	mov	w9, #1
	str	w9, [x19, #TR_SRC]
	BADDR	x9, E_ST
	str	x9, [x19, #TR_ST]
	mov	x0, #(FIFO_N * 8)
	bl	_malloc
	str	x0, [x19, #TR_FQ]
	cbz	x0, Lret1
	mov	x0, x19
	bl	txt_fd
	str	x19, [x27, #E_CCT]
	mov	x0, x19
	b	Lret1

; media_next(p, type) -> x0 = the next #EXT-X-MEDIA line from p with that TYPE=..., x1 = its end, x2 = the line after it; x0 = 0 at the end.
media_next:
	FRAME	3
	mov	x19, x0
	mov	x20, x1
Lmx_line:
	ldrb	w9, [x19]
	cbz	w9, Lmx_none
	mov	x0, x19
	bl	line_end
	mov	x21, x0
	mov	x22, x1
	mov	x0, x19
	CSTR	x1, "#EXT-X-MEDIA:"
	mov	x2, #13
	bl	_strncmp
	cbnz	w0, Lmx_next
	mov	x0, x19
	mov	x1, x20
	sub	x2, x21, x19
	bl	_strnstr
	cbnz	x0, Lmx_found
Lmx_next:
	mov	x19, x22
	b	Lmx_line
Lmx_found:
	mov	x0, x19
	mov	x1, x21
	mov	x2, x22
	b	Lret3
Lmx_none:
	mov	x0, #0
	b	Lret3

; uri_is(line, end, url) -> w0 = 1 if the URL (0: none) ends with the line's URI.
uri_is:
	FRAME	2
	mov	x19, x3
	mov	w20, #0
	cbz	x19, 1f
	CSTR	x2, "URI="
	bl	attr
	cbz	x0, 1f
	mov	x21, x0
	sub	x22, x1, x0
	mov	x0, x19
	bl	_strlen
	subs	x0, x0, x22
	b.lo	1f
	add	x0, x19, x0
	mov	x1, x21
	mov	x2, x22
	bl	_memcmp
	cmp	w0, #0
	cset	w20, eq
1:	mov	w0, w20
	b	Lret2

; eng_pick(choice) — a track picked: subtitles (index, -1 none) or, with bit 32, a sound track of the file, or an HLS rendition (0x1000 + its index); it plays from now.
	ENTRY	eng_pick
	FRAME	2
	mov	x20, x0
	BADDR	x0, (E_ST + 2 * ST_SIZE)  ; a subtitle rendition's stream stops
	tbnz	x20, #32, 2f
	bl	st_close
2:	mov	x0, x20
	mov	x19, #0
	tbnz	w0, #31, 1f
	cmp	w0, #0x1000
	b.hs	Lpk_hls
	ldr	w9, [x27, #E_NTR]
	cmp	w0, w9
	b.hs	Lret2                     ; other media now
	BADDR	x19, E_TR
	mov	w9, w0
	add	x19, x19, x9, lsl #9
	ldr	w9, [x19, #TR_KIND]
	mov	w10, #'s'
	mov	w11, #'a'
	tst	x0, #(1 << 32)
	csel	w10, w11, w10, ne
	cmp	w9, w10
	b.ne	Lret2
1:	tbnz	x0, #32, Lpk_sound
	str	x19, [x27, #E_SUBT]
	bl	now_ms
	bl	sub_seek
	b	Lret2
Lpk_sound:
	ldr	x9, [x27, #E_AT]
	ldr	w10, [x19, #TR_SRC]
	cmp	x9, x19
	ccmp	w10, #0, #0, ne           ; a stream's track stays with its stream
	b.ne	Lret2
	str	x19, [x27, #E_AT]
	bl	now_ms
	mov	x3, x0
	mov	x0, x19
	ldr	x1, [x27, #E_AR]
	ADDR	x2, Lblk_a
	bl	trk_play
	b	Lret2
Lpk_hls:
	cmp	w20, #0x2000
	b.lo	1f
	bl	cc_track                  ; CC1: the picture's captions from now
	cbz	x0, Lret2
	str	x0, [x27, #E_SUBT]
	bl	now_ms
	bl	sub_seek
	b	Lret2
1:	ldr	x19, [x27, #E_MASTER]
	cbz	x19, Lret2
	CSTR	x1, "TYPE=AUDIO"
	CSTR	x9, "TYPE=SUBTITLES"
	tst	x20, #(1 << 32)
	csel	x21, x1, x9, ne
	and	w22, w20, #0xfff          ; the index-th of its type
1:	mov	x0, x19
	mov	x1, x21
	bl	media_next
	cbz	x0, Lret2                 ; other media now
	mov	x19, x2
	subs	w22, w22, #1
	b.hs	1b
	CSTR	x2, "URI="
	bl	attr
	cbz	x0, Lret2
	mov	x2, x1
	mov	x1, x0
	ldr	x0, [x27, #E_MURL]
	bl	url_join
	cbz	x0, Lret2
	mov	x21, x0                   ; its playlist
	tbnz	x20, #32, Lpk_hsound
	BADDR	x19, (E_ST + 2 * ST_SIZE) ; subtitles: their own stream feeds the shown track
	ldr	x22, [x19, #ST_TR]
	cbnz	x22, 2f
	mov	x0, x19
	mov	w1, #'s'
	mov	w2, #1000                 ; ms
	bl	trk_new
	mov	x22, x0
	cbz	x0, Lpk_free
	mov	x0, x22                   ; its cues come as tx3g samples
	bl	txt_fd
2:	mov	x0, x19
	mov	x1, x21
	bl	pl_set
	str	x22, [x27, #E_SUBT]
	bl	now_ms
	mov	x20, x0
	bl	sub_seek
	mov	x0, x19
	mov	x1, x20
	bl	st_seek
	b	Lret2
Lpk_hsound:
	ldr	x0, [x27, #E_AR]          ; sound: the rendition's stream from now, the old sound dropped
	SEND	S_stopRequestingMediaData
	ldr	x0, [x27, #E_AR]
	SEND	S_flush
	BADDR	x19, (E_ST + ST_SIZE)
	mov	x0, x19
	mov	x1, x21
	bl	pl_set
	bl	now_ms
	mov	x1, x0
	mov	x0, x19
	bl	st_seek
	b	Lret2
Lpk_free:
	mov	x0, x21
	bl	_free
	b	Lret2

; act_option(item) — a subtitle or sound track picked: This Mac's item switches to it (tag -1: subtitles off).
	ENTRY	act_option
	FRAME	2
	mov	x19, x2
	ldr	w9, [x28, #G_MODE]
	cbnz	w9, Lot_av
	mov	x0, x19                   ; the engine's: picked on its queue
	SEND	S_tag
	mov	w20, w0
	mov	x0, x19
	SEND	S_menu
	ldr	x9, [x28, #G_SUBMENU]
	cmp	x0, x9
	cset	x9, ne
	mov	w1, w20
	orr	x1, x1, x9, lsl #32
	adr	x0, eng_pick
	bl	eng_cmd
	b	Lret2
Lot_av:
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
	ldr	w9, [x28, #G_MODE]
	cbnz	w9, Lpi_av
	ldr	x19, [x27, #B_PIPE]       ; the engine's picture: its sample buffer layer, played through this controller's PiP methods
	cbnz	x19, Lpi_toggle
	CLASS	x0, AVPictureInPictureControllerContentSource
	SEND	S_alloc
	ldr	x2, [x28, #G_SBLAYER]
	ldr	x3, [x28, #G_CTRL]
	SEND	S_initWithSampleBufferDisplayLayer_playbackDelegate_
	mov	x19, x0
	CLASS	x0, AVPictureInPictureController
	SEND	S_alloc
	mov	x2, x19
	SEND	S_initWithContentSource_
	mov	x19, x0
	str	x0, [x27, #B_PIPE]
	cbnz	x0, Lpi_toggle
	b	Lret1
Lpi_av:
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

; pip_play(self, _cmd, controller, playing) — PiP's play button: This Mac plays or pauses.
	ENTRY	pip_play
	ldr	w9, [x28, #G_PLAYING]
	cmp	w9, w3
	b.ne	local_toggle
	ret

; pip_range(self, _cmd, controller) -> CMTimeRange (x8): the media's length, endless when unknown or live.
	ENTRY	pip_range
	ldr	x9, [x27, #E_DURMS]
	mov	x10, #1000
	movk	x10, #1, lsl #32          ; ms, valid
	stp	xzr, x10, [x8]
	str	xzr, [x8, #16]
	mov	x11, #(5 << 32)           ; valid, +infinity
	cmp	x9, #0
	csel	x10, x10, x11, ne
	stp	x9, x10, [x8, #24]
	str	xzr, [x8, #40]
	ret

; pip_paused(self, _cmd, controller) -> w0 = This Mac is paused.
	ENTRY	pip_paused
	ldr	w0, [x28, #G_PLAYING]
	eor	w0, w0, #1
	ret

; pip_skip(self, _cmd, controller, interval, handler) — PiP's skip buttons: a seek by the interval, then the handler.
	ENTRY	pip_skip
	FRAME	1
	mov	x19, x4
	ldr	x9, [x3]
	ldrsw	x10, [x3, #8]
	mov	x11, #1000
	mul	x9, x9, x11
	sdiv	x20, x9, x10
	bl	now_ms
	adds	x0, x0, x20
	csel	x0, x0, xzr, gt
	bl	local_seekms
	ldr	x16, [x19, #16]
	mov	x0, x19
	blr	x16
	b	Lret1

; act_layout — the window was resized (or went full screen).
	ENTRY	act_layout
	b	layout_stage

; imp_yes -> YES: the last window closing quits; the canvas takes the keyboard; a drag is a copy.
imp_yes:
	mov	w0, #1
	ret

; ---- Construction ----

; ---- Entry point ----

; main() — the registry, then services, the app with its menus and window and the poll timer; then the run loop.
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
	BADDR	x9, B_CLS
	cmp	x20, x9
	b.hs	Lmn_cls
	mov	x1, x19
	mov	x0, #-2                   ; RTLD_DEFAULT
	bl	_dlsym
	b	Lmn_store
Lmn_cls:
	bl	_objc_getClass
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
	ldr	x9, [x27, #F__NSConcreteGlobalBlock]
	ADDR	x10, Lblk_v
	str	x9, [x10]
	str	x9, [x10, #(Lblk_a - Lblk_v)]
	str	x9, [x10, #(Lblk_s - Lblk_v)]
	mov	w9, #100
	str	w9, [x28, #G_VOLPCT]
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
	bl	local_poll
	ADDR	x0, Lprog_show
	bl	ui_run
	bl	layout_stage
	adr	x0, eng_init
	mov	x1, #0
	bl	eng_cmd
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
	.equ G_SEP,	G_T3                  ; a separator item
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
	CALL	F_signal, "II"            ; a vanished client must not kill the app
	.byte	SIGPIPE, SIG_IGN
	CALL	F_dispatch_get_global_queue, "=II"
	.byte	QOS_CLASS_USER_INITIATED, 0
	STO	G_WORKQ
	CALL	F_dispatch_queue_attr_make_with_autorelease_frequency, "=II"
	.byte	0, 1                      ; serial, a pool per work item
	CALL	F_dispatch_queue_attr_make_with_qos_class, "=VII"
	.byte	QOS_CLASS_USER_INTERACTIVE, 0
	CALL	F_dispatch_queue_create, "=CV"
	.asciz	"beam.media"
	STO	G_MEDIAQ

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
	METHOD	"act_focus:", act_focus
	METHOD	"act_open:", act_open
	METHOD	"act_aonly:", act_aonly
	METHOD	"menuNeedsUpdate:", act_options
	METHOD	"act_speed:", act_speed
	METHOD	"act_option:", act_option
	METHOD	"act_pip:", act_pip
	METHOD	"routePickerViewWillBeginPresentingRoutes:", air_prepare
	METHOD	"pictureInPictureController:setPlaying:", pip_play, "v@:@B"
	METHOD	"pictureInPictureControllerTimeRangeForPlayback:", pip_range, "{?={?=qiIq}{?=qiIq}}@:@"
	METHOD	"pictureInPictureControllerIsPlaybackPaused:", pip_paused, "B@:@"
	METHOD	"pictureInPictureController:didTransitionToRenderSize:", imp_yes, "v@:@{?=ii}"
	METHOD	"pictureInPictureController:skipByInterval:completionHandler:", pip_skip, "v@:@{?=qiIq}@?"
	METHOD	"windowDidResize:", act_layout
	METHOD	"control:textView:doCommandBySelector:", act_urlcmd, "B@:@@:"
	METHOD	"application:openURLs:", act_openurls, "v@:@@"
	METHOD	"URLSession:dataTask:didReceiveData:", act_netdata, "v@:@@@"
	METHOD	"URLSession:task:didCompleteWithError:", act_netdone, "v@:@@@"
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

	; The pictures, fitted to the window: the engine's (its layer comes from the media queue), then AVPlayer's.
	NEWV	NSView, 0, 0, WIN_W, WIN_H
	STO	G_SBV
	MASKV	AR_WIDTH | AR_HEIGHT
	MSG	S_setHidden_, "I"
	.byte	1
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
	LABELIN	G_CUR, G_BAR, "", 16, ROW1_Y + 2, TIME_W, LABEL_H, 0, G_SECOND, AR_RIGHT
	LABELIN	G_DUR, G_BAR, "", BAR_W - 16 - TIME_W, ROW1_Y + 2, TIME_W, LABEL_H, 2, G_SECOND, AR_LEFT
	SLIDERIN	G_POS, G_BAR, "act_seek:", 24 + TIME_W, ROW1_Y, BAR_W - 2 * (24 + TIME_W), 1, AR_WIDTH
	FONT	S_systemFontOfSize_weight_, 13, X_SEMIBOLD
	LABELIN	G_TITLE, G_BAR, "", 16, ROW2_C - 9, TEXT_W, 18, 0, G_TEXT, AR_WIDTH | AR_RIGHT
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
	MSG	S_setDelegate_, "O"           ; air_prepare as it opens
	.byte	G_CTRL >> 3
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

	; Open from URL: a field floating in the middle of the stage (placed by layout_stage).
	NEWV	NSView, 0, 0, URL_W, URL_H
	STO	G_URLBOX
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
	.asciz	"Link or search"
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

; The engine's layer into its view, laid out by pic_layout.
Lprog_attach:
	LD	G_SBV
	MSG	S_setWantsLayer_, "I"
	.byte	1
	MSG	S_layer, "="
	MSG	S_addSublayer_, "O"
	.byte	G_SBLAYER >> 3
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
Lep_guide:	.asciz	"https://www.youtube.com/youtubei/v1/guide?prettyPrint=false", "X-Goog-FieldMask", "responseContext.visitorData", ""
Lep_search:	.asciz	"https://www.youtube.com/youtubei/v1/search?prettyPrint=false", "X-Goog-FieldMask", "contents,responseContext.visitorData", ""
Lep_player:	.asciz	"https://www.youtube.com/youtubei/v1/player?prettyPrint=false", "X-Goog-FieldMask", "streamingData,videoDetails,playabilityStatus,responseContext.visitorData", ""

; Headers of every InnerTube request.
Lapi_headers:
	.asciz	"Content-Type", "application/json"
	.asciz	"Origin", "https://www.youtube.com"
	.asciz	"Accept-Language", "en-US,en;q=0.9"
	.byte	0

; InnerTube clients: User-Agent, context fields, headers. The player chain is tried in order: VISIONOS URLs serve whole streams, the rest cover what it refuses.
Lclients:
	.short	Lcl2 - Lclients
	.asciz	"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
	.asciz	"\"clientName\":\"VISIONOS\",\"clientVersion\":\"1.02\",\"osName\":\"visionOS\",\"osVersion\":\"26.5.23O471\",\"deviceModel\":\"RealityDevice17,1\",\"deviceMake\":\"Apple\","
	.asciz	"X-YouTube-Client-Name", "101"
	.asciz	"X-YouTube-Client-Version", "1.02"
	.byte	0
Lcl2:
	.short	Lcl3 - Lcl2
	.asciz	"com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; en_US) gzip"
	.asciz	"\"clientName\":\"ANDROID_VR\",\"clientVersion\":\"1.65.10\",\"osName\":\"Android\",\"osVersion\":\"12L\",\"deviceModel\":\"Quest 3\",\"androidSdkVersion\":32,"
	.asciz	"X-YouTube-Client-Name", "28"
	.asciz	"X-YouTube-Client-Version", "1.65.10"
	.byte	0
Lcl3:
	.short	Lcl4 - Lcl3
Lc_android:	                          ; also the search client
	.asciz	"com.google.android.youtube/20.10.38 (Linux; U; Android 14; en_US) gzip"
	.asciz	"\"clientName\":\"ANDROID\",\"clientVersion\":\"20.10.38\",\"osName\":\"Android\",\"osVersion\":\"14\",\"androidSdkVersion\":34,"
	.asciz	"X-YouTube-Client-Name", "3"
	.asciz	"X-YouTube-Client-Version", "20.10.38"
	.byte	0
Lcl4:
	.short	Lcl5 - Lcl4
	.asciz	"com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X; en_US)"
	.asciz	"\"clientName\":\"IOS\",\"clientVersion\":\"20.10.4\",\"osName\":\"iOS\",\"osVersion\":\"18.3.2.22D82\",\"deviceModel\":\"iPhone16,2\","
	.asciz	"X-YouTube-Client-Name", "5"
	.asciz	"X-YouTube-Client-Version", "20.10.4"
	.byte	0
Lcl5:
	.short	0
Lc_web:	                                  ; the visitorData client
	.asciz	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
	.asciz	"\"clientName\":\"WEB\",\"clientVersion\":\"2.20260114.08.00\",\"osName\":\"Windows\",\"osVersion\":\"10.0\","
	.asciz	"X-YouTube-Client-Name", "1"
	.asciz	"X-YouTube-Client-Version", "2.20260114.08.00"
	.byte	0

; The registry's names, in its order.
.macro REG sym, name
	.asciz	"\name"
.endm
.macro REGSEL
.endm
.macro REGCLS
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
