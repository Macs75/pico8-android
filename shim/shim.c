// i forgot why this define is here
#define _GNU_SOURCE

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/types.h>
#include <fcntl.h>
#include <string.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <errno.h>
#include <SDL2/SDL.h>

#define FINDSDL(VAR, NAME) \
    if (!(VAR)) { \
        VAR = dlsym(RTLD_NEXT, #NAME); \
        if (!(VAR)) { \
            fprintf(stderr, "Error: could not find %s\n", #NAME); \
            abort(); \
        } \
    }

static int vid_fd = -1;
static int in_fd = -1;

#define FIFO_VID_PATH "/tmp/pico8.vid"
#define FIFO_IN_PATH "/tmp/pico8.in"

static Uint8 keystate[256];

static uint8_t* picoram = NULL;
#define PICORAM_INDEX_ISINEDITOR 0x2586c
#define PICORAM_INDEX_ISINGAME 0x25868
// this address is garbage lol
#define PICORAM_INDEX_ISPAUSED 0x3726c
// devkit address is *probably* correct?
#define PICORAM_INDEX_DEVKIT 0x2c8e5

#define PIDOT_EVENT_MOUSEEV 1
#define PIDOT_EVENT_KEYEV 2
#define PIDOT_EVENT_CHAREV 3

#define IN_PACKET_SIZE 8 // Event(1) + X(2) + Y(2) + Mask(1) + Pad(2)
static uint8_t in_packet[IN_PACKET_SIZE];
#define HEADER_SIZE 11 // "PICO8SYNC__"
#define META_SIZE 1
#define PIXEL_SIZE (128*128*4)
#define TOTAL_PACKET_SIZE (HEADER_SIZE + META_SIZE + PIXEL_SIZE)

// Helper to ensure all bytes are written to a potentially blocking FD
static ssize_t write_all(int fd, const void* buf, size_t len) {
    size_t total_sent = 0;
    const uint8_t* p = (const uint8_t*)buf;
    while (total_sent < len) {
        ssize_t sent = write(fd, p + total_sent, len - total_sent);
        if (sent <= 0) {
            if (sent < 0 && errno == EINTR) continue;
            return sent; // Error or broken pipe
        }
        total_sent += sent;
    }
    return total_sent;
}

void shim_fifo_init() {
    printf("SHIM: Using Host-Created FIFOs at %s and %s\n", FIFO_IN_PATH, FIFO_VID_PATH);
    
    // Eagerly open Input FIFO so Godot (Writer) has a target
    in_fd = open(FIFO_IN_PATH, O_RDONLY | O_NONBLOCK);
    if (in_fd < 0) {
        perror("SHIM: Failed to open Input FIFO eagerly");
    } else {
        printf("SHIM: Input FIFO opened eagerly\n");
    }
}


// Try to read a packet from the client
// Returns true if a full packet was read
static bool pico_poll_event() {
    // Check if open (eagerly opened in init, but maybe failed/closed)
    if (in_fd < 0) {
        // Try to reopen
        in_fd = open(FIFO_IN_PATH, O_RDONLY | O_NONBLOCK);
        if (in_fd < 0) return false;
        printf("SHIM: Connected to Input FIFO (Lazy/Retry)\n");
    }

    ssize_t n = read(in_fd, in_packet, IN_PACKET_SIZE);
    if (n == IN_PACKET_SIZE) {
        return true;
    } else if (n < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            // No data available
        } else {
            close(in_fd);
            in_fd = -1;
        }
    } else if (n == 0) {
        // EOF means writer closed pipe or no writer connected in non-blocking
        // Don't close immediately to prevent spamming open()
        close(in_fd);
        in_fd = -1;
    }
    return false;
}

static bool false_start = true;

DECLSPEC int SDLCALL SDL_Init(Uint32 flags) {
    static int (*realf)(Uint32) = NULL;
    FINDSDL(realf, SDL_Init);

    if (false_start) {
        printf("false start\n");
        false_start = false;
    } else {
        shim_fifo_init();
    }

    return realf(flags);
}

static SDL_Surface* currentsurf = NULL;

DECLSPEC SDL_Window* SDLCALL SDL_CreateWindow(const char *title,
                                                      int x, int y, int w,
                                                      int h, Uint32 flags) {
    static SDL_Window* (*realf)(const char*, int, int, int, int, Uint32) = NULL;
    FINDSDL(realf, SDL_CreateWindow);
    printf("SDL_CreateWindow(*,*,*,*,*,%d)\n", flags);
    flags &= ~(SDL_WINDOW_FULLSCREEN_DESKTOP | SDL_WINDOW_RESIZABLE);
    SDL_Window* window = realf(title, x, y, 128, 128, flags);
    currentsurf = SDL_GetWindowSurface(window);
    printf("yoinking surface. ptr=%p\n", currentsurf);
    if(currentsurf) {
        printf("surface format: %s\n", SDL_GetPixelFormatName(currentsurf->format->format));
    }
    return window;
}

static Uint64 last_frame = 0;

// Single static buffer to avoid stack allocation and allow single-syscall writing
static uint8_t packet_buffer[TOTAL_PACKET_SIZE];
static bool header_initialized = false;
static int vid_open_attempts = 0;

void pico_send_vid_data() {
    if (currentsurf == NULL) {
        return;
    }

        // Initialize header once
        if (!header_initialized) {
            memcpy(packet_buffer, "PICO8SYNC__", HEADER_SIZE);
            header_initialized = true;
        }

        // Destination is always RGBA8888 (Godot format)
        // Skip Header + Meta to get to pixel area
        uint32_t* dst32 = (uint32_t*)(packet_buffer + HEADER_SIZE + META_SIZE); 
        
        // 32-bit stride 00RRGGBB (for RGB888) or XXRRGGBB (for XRGB8888)
        const uint32_t* src32 = (uint32_t*)currentsurf->pixels;
        for (int i = 0; i < 16384; i++) {
        uint32_t pixel = src32[i];
        *dst32++ = ((pixel & 0x00FF0000) >> 16) | 
                    (pixel & 0x0000FF00)         | 
                    ((pixel & 0x000000FF) << 16) | 
                    0xFF000000;
        }

        uint8_t navstate = 0x00;
        if (picoram != NULL) {
            if (picoram[PICORAM_INDEX_ISINEDITOR]) {
                navstate |= 0x01;
            }
            if (picoram[PICORAM_INDEX_ISINGAME]) {
                navstate |= 0x02;
            }
            if (picoram[PICORAM_INDEX_DEVKIT] & 0x1) {
                navstate |= 0x04;
            }
        }
        
        // Write Metadata
        packet_buffer[HEADER_SIZE] = navstate;

        // DIRECT FIFO SEND
        
        // 1. Lazy open Video FIFO
        if (vid_fd < 0) {
            // OPEN IN BLOCKING MODE for video. 
            // This ensures we wait for Godot to clear the buffer if we exceed PIPE_BUF (64KB).
            vid_fd = open(FIFO_VID_PATH, O_WRONLY);
            if (vid_fd < 0) {
                // If ENXIO, no reader is open yet. This is expected.
                if (errno != ENXIO) {
                   perror("SHIM: Failed to open video FIFO");
                } else {
                   if (vid_open_attempts++ % 60 == 0) {
                       printf("SHIM: Waiting for video reader (ENXIO)...\n");
                   }
                }
                return;
            }
            
            // Optimization: Increase pipe capacity to 1MB (default is 64KB)
            // This prevents blocking when writing ~65KB frames
            int pipe_sz = fcntl(vid_fd, F_SETPIPE_SZ, 1048576);
            if (pipe_sz < 0) {
                // Not fatal, just means we use default size
                // perror("SHIM: Failed to set pipe capacity"); 
            } else {
                printf("SHIM: Video FIFO capacity set to %d bytes\n", pipe_sz);
            }

            printf("SHIM: Connected to Video FIFO!\n");
        }

        // 2. Write Data
        if (vid_fd >= 0) {
            ssize_t sent = write_all(vid_fd, packet_buffer, TOTAL_PACKET_SIZE);
            if (sent < 0) {
                 if (errno == EPIPE) {
                     // Reader Closed
                     printf("SHIM: Video Pipe broken (Reader closed)\n");
                     close(vid_fd);
                     vid_fd = -1;
                 } else if (errno != EAGAIN) {
                     // Other error
                     // perror("SHIM: Write failed");
                 }
            }
        }

}

DECLSPEC int SDLCALL SDL_UpdateWindowSurface(SDL_Window * window) {
    static int (*realf)(SDL_Window*) = NULL;
    FINDSDL(realf, SDL_UpdateWindowSurface);
    // printf("we are so UpdateWindowSurfacing\n");
    pico_send_vid_data();
    return realf(window);
}

DECLSPEC void SDLCALL SDL_RenderPresent(SDL_Renderer * renderer) {
    static void (*realf)(SDL_Renderer*) = NULL;
    FINDSDL(realf, SDL_RenderPresent);
    // printf("we are so RenderPresenting\n");
    pico_send_vid_data();
    return realf(renderer);
}

DECLSPEC SDL_Surface * SDLCALL SDL_GetWindowSurface(SDL_Window * window) {
    static SDL_Surface* (*realf)(SDL_Window* window) = NULL;
    FINDSDL(realf, SDL_GetWindowSurface);
    if (currentsurf == NULL) {
        printf("yoinking surface\n");
    }
    return currentsurf = realf(window);
}

static int mousex = 0;
static int mousey = 0;
static Uint32 mouseb = 0;

static Uint32 lastmod = 0;

DECLSPEC int SDLCALL SDL_PollEvent(SDL_Event * event) {
    static int (*realf)(SDL_Event* event) = NULL;
    FINDSDL(realf, SDL_PollEvent);
    int ret = realf(event);
    if (ret == 1) {
        printf("event %d\n", event->type);
        if (
            event->type == SDL_WINDOWEVENT
        // || event->type == SDL_TEXTINPUT
        ) {
            printf("blocking\n");
            return 0;
        }
        if (event->type == SDL_KEYDOWN || event->type == SDL_KEYUP) {
            event->key.keysym.sym = 0;
            if (event->key.keysym.scancode == SDLK_LCTRL) {
                event->key.keysym.mod = 0;
            }
            // printf(
            //     "KEYEV\n%d %d %d %d %d %d\n",
            //     event->key.windowID,
            //     event->key.state,
            //     event->key.repeat,
            //     event->key.keysym.scancode,
            //     event->key.keysym.sym,
            //     event->key.keysym.mod
            // );
            /*
            typedef struct SDL_KeyboardEvent
            {
                Uint32 type;        /**< ::SDL_KEYDOWN or ::SDL_KEYUP * /
                Uint32 timestamp;   /**< In milliseconds, populated using SDL_GetTicks() * /
                Uint32 windowID;    /**< The window with keyboard focus, if any * /
                Uint8 state;        /**< ::SDL_PRESSED or ::SDL_RELEASED * /
                Uint8 repeat;       /**< Non-zero if this is a key repeat * /
                Uint8 padding2;
                Uint8 padding3;
                SDL_Keysym keysym;  /**< The key that was pressed or released * /
            } SDL_KeyboardEvent;
            */
            // PICO-8, surprisingly, uses scancode
            // // event->key.keysym.scancode = 0;
            // // event->type = SDL_FIRSTEVENT;
        }

        // if (event->type == SDL_TEXTINPUT) {
        //     printf(
        //         "CHAREV\n%02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x\n%s\n",
        //         event->text.text[0], event->text.text[1], event->text.text[2], event->text.text[3], event->text.text[4], event->text.text[5], event->text.text[6], event->text.text[7], event->text.text[8], event->text.text[9], event->text.text[10], event->text.text[11], event->text.text[12], event->text.text[13], event->text.text[14], event->text.text[15], event->text.text[16], event->text.text[17], event->text.text[18], event->text.text[19], event->text.text[20], event->text.text[21], event->text.text[22], event->text.text[23], event->text.text[24], event->text.text[25], event->text.text[26], event->text.text[27], event->text.text[28], event->text.text[29], event->text.text[30], event->text.text[31],
        //         &event->text.text
        //     );
        // }
    } else {
        int result = pico_poll_event();
        // printf("result %d\n", result);
        if (result == true) {
            switch (in_packet[0])
            {
                case PIDOT_EVENT_MOUSEEV:
                    event->type = SDL_FIRSTEVENT;
                    mousex = in_packet[1];
                    mousey = in_packet[2];
                    mouseb = in_packet[3];
                    return 1;
                case PIDOT_EVENT_KEYEV:
                    event->type = event->key.type = in_packet[2] ? SDL_KEYDOWN : SDL_KEYUP;
                    event->key.timestamp = SDL_GetTicks();
                    event->key.windowID = 1;
                    event->key.state = in_packet[2] ? SDL_PRESSED : SDL_RELEASED;
                    event->key.repeat = in_packet[3];
                    event->key.keysym.scancode = in_packet[1];
                    keystate[in_packet[1]] = in_packet[2];
                    event->key.keysym.mod = in_packet[4] + (((Uint16)in_packet[5])<<8);
                    lastmod = event->key.keysym.mod;
                    // printf(
                    //     "FAKE KEYEV\n%d %d %d %d %d %d\n",
                    //     event->key.windowID,
                    //     event->key.state,
                    //     event->key.repeat,
                    //     event->key.keysym.scancode,
                    //     event->key.keysym.sym,
                    //     event->key.keysym.mod
                    // );
                    // if (in_packet[1] == 57 && in_packet[2] == 1) { // uncomment if you need memdumps, then use caps lock
                    //     static char fname[64];
                    //     static int snapcount;
                    //     sprintf(fname, "memdump%03d.dat", snapcount++);
                    //     FILE *file = fopen(fname, "wb");
                    //     if (!file) {
                    //         perror("Failed to open file");
                    //     } else {
                    //         // data, size per item, item count, file
                    //         fwrite(picoram, 1, 0x372b8, file);

                    //         fclose(file);
                    //     }
                    // }
                    return 1;
                case PIDOT_EVENT_CHAREV:
                    event->type = event->text.type = SDL_TEXTINPUT;
                    event->text.timestamp = SDL_GetTicks();
                    event->text.windowID = 1;
                    event->text.text[0] = in_packet[1];
                    event->text.text[1] = 0;
                    return 1;
                default:
                    break;
            }
        }
    }
    return ret;
}

DECLSPEC Uint32 SDLCALL SDL_GetMouseState(int *x, int *y) {
    *x = mousex;
    *y = mousey;
    return mouseb;
}

DECLSPEC SDL_Keymod SDLCALL SDL_GetModState(void) {
    static SDL_Keymod (*realf)() = NULL;
    FINDSDL(realf, SDL_GetModState);
    // printf("mod %d real %d\n", lastmod, realf());
    return lastmod;
}

DECLSPEC const Uint8 *SDLCALL SDL_GetKeyboardState(int *numkeys) {
    *numkeys = 256;
    return keystate;
}

// static bool recursive_malloc = false;
// void *malloc (size_t __size) {
//     static void* (*realf)(size_t) = NULL;
//     FINDSDL(realf, malloc);
//     if (!recursive_malloc) {
//         recursive_malloc = true;
//         printf("MALLOC with size %d\n", __size);
//         recursive_malloc = false;
//     }
//     return realf(__size);
// }

void *memset (void *__s, int __c, size_t __n) {
    static void* (*realf)(void*, int, size_t) = NULL;
    FINDSDL(realf, memset);
    if (__c == 0 && __n == 0x372b8) {
        // printf("PICO-8 RAM identified\n");
        picoram = __s;
    }
    return realf(__s, __c, __n);
}