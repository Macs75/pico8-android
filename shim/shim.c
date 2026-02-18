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
#include <link.h> // For dl_iterate_phdr

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
static size_t picoram_size = 0;

// Version Guarding
#define PICO8_VERSION_0_2_7_SIZE 1640888
static bool is_version_0_2_7 = false;

// #define MAX_CANDIDATES 16
// typedef struct {
//     void* ptr;
//     size_t size;
// } MemCandidate;
// static MemCandidate candidates[MAX_CANDIDATES];
// static int candidate_count = 0;

// 0.2.7 Memory locations
// Found via 4-way memdump analysis (Take 2)
#define PICORAM_INDEX_ISINEDITOR 0x25700
#define PICORAM_INDEX_ISINGAME 0x257d4
// 11 = Editor/Menu, 27 = Game
#define PICORAM_INDEX_STATE_TYPE 0x2572c
// Cart Loaded Flag: 0=Splore (No Cart), 1=Editor/Console/Game (Cart Loaded)
#define PICORAM_INDEX_CART_LOADED 0x14
// Strict flags
#define PICORAM_INDEX_STRICT_EDITOR 0x255d4
#define PICORAM_INDEX_INPUT_MODE 0x1

// Devkit Flag: DAT_006516b4.
// Offset: 0x6516b4 - 0x61af80 = 0x36734.
#define PICORAM_INDEX_DEVKIT 0x36734

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

static int header_handler(struct dl_phdr_info *info, size_t size, void *data) {
    // printf("SHIM: dl_iterate_phdr found: '%s' at %p\n", info->dlpi_name, (void*)info->dlpi_addr);
    
    // The main executable often has an empty name
    if (strlen(info->dlpi_name) == 0) {
        printf("SHIM: Found Main Executable (Empty Name) at 0x%lx\n", info->dlpi_addr);
        *(uintptr_t*)data = info->dlpi_addr;
        return 1;
    }
    
    // Or check for "pico8"
    if (strstr(info->dlpi_name, "pico8")) {
        printf("SHIM: Found PICO-8 binary by name at 0x%lx\n", info->dlpi_addr);
        *(uintptr_t*)data = info->dlpi_addr;
        return 1;
    }
    return 0;
}

// Helper to get base address
static uintptr_t get_base_address() {
    uintptr_t base = 0;
    dl_iterate_phdr(header_handler, &base);
    return base;
}

//simple check for file size for speed reasons
static void check_pico8_version() {
    struct stat st;
    if (stat("/proc/self/exe", &st) == 0) {
        if (st.st_size == PICO8_VERSION_0_2_7_SIZE) {
            is_version_0_2_7 = true;
            printf("SHIM: PICO-8 Version 0.2.7 DETECTED (Size: %ld bytes). Advanced features enabled.\n", st.st_size);
        } else {
            is_version_0_2_7 = false;
            printf("SHIM: PICO-8 Version Mismatch (Size: %ld bytes). Expected %d for 0.2.7.\n", st.st_size, PICO8_VERSION_0_2_7_SIZE);
            printf("SHIM: Safe Mode Enabled (Input/Video only, no Auto-Pause/Keyboard/Splore detection).\n");
        }
    } else {
        perror("SHIM: Failed to stat /proc/self/exe");
    }
}

static uintptr_t base_addr = 0;

void shim_fifo_init() {
    printf("SHIM: Using Host-Created FIFOs at %s and %s\n", FIFO_IN_PATH, FIFO_VID_PATH);
    
    // Check version immediately
    check_pico8_version();
    
    // Eagerly open Input FIFO so Godot (Writer) has a target
    in_fd = open(FIFO_IN_PATH, O_RDONLY | O_NONBLOCK);
    if (in_fd < 0) {
        perror("SHIM: Failed to open Input FIFO eagerly");
    } else {
        printf("SHIM: Input FIFO opened eagerly\n");
    }
    
    // Find base address eagerly to fail fast if missed
    base_addr = get_base_address();
    printf("SHIM: Initial Base Address Scan: 0x%lx\n", base_addr);
    fflush(stdout);
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

        uint8_t navstate = 0;
        uint8_t state_enum = 0;
        uint8_t cart_loaded = 0;
        uint8_t input_mode = 0;
        uint8_t is_editor = 0;



        // Gate memory reading behind version check to prevent reading garbage/crashing
        if (picoram != NULL && is_version_0_2_7) {
            state_enum = picoram[PICORAM_INDEX_STATE_TYPE];
            cart_loaded = picoram[PICORAM_INDEX_CART_LOADED];
            input_mode = picoram[PICORAM_INDEX_INPUT_MODE];
            uint8_t splore_page = picoram[0x36da8]; // 0x36da8 == 2 is Splore Page (Confirmed via decompilation)
            
            // Paused Detection via App Struct (BSS)
            // base_addr is found in shim_fifo_init via dl_iterate_phdr
            
            // Runtime Picoram: 0x300051af80. Runtime Base: 0x3000000000. Offset: 0x51af80.
            // Ghidra Picoram: 0x61af80.
            // Difference: 0x100000 (Ghidra Image Base).
            // Ghidra App: 0x2a0e60.
            // Real Offset: 0x2a0e60 - 0x100000 = 0x1a0e60.
            
            uint8_t is_paused = 0;
            
            if (base_addr != 0) {
                uint8_t *app_struct = (uint8_t *)(base_addr + 0x1a0e60);
                // Safe access assuming mapping is valid
                // CORRECTION: 5080 and 5092 are DECIMAL offsets (from Ghidra naming app._5080_4_)
                // 5080 = 0x13d8. 5092 = 0x13e4.
                is_paused = (app_struct[5080] != 0 || app_struct[5092] != 0);
            }

            is_editor = (picoram[PICORAM_INDEX_STRICT_EDITOR] > 0); // > 0 to catch Music/Sprite tabs (Value 2)
            
            // Global flag: Cart Loaded (0x20)
            if (cart_loaded == 1) {
                navstate |= 0x20;
            }
            
            // Global flag: Paused (0x40) - Independent check
            // Used to detect Pause Menu in Game, but allows seeing it in other states too.
            if (is_paused) {
                navstate |= 0x40;
            }

            // Game Check (Highest Priority)
            // If we are in Game Mode (27) OR the IsGame flag is set, we are playing.
            if (state_enum == 27 || picoram[PICORAM_INDEX_ISINGAME]) {
                navstate |= 0x02; // G
            }
            // System Mode Check (Only if not in Game)
            else if (state_enum == 11) {
                
                // Editor Check
                if (is_editor) {
                    navstate |= 0x01; // E
                }
                // Splore Check
                // Decompiled code sets 0x... = 2 when entering Splore.
                // Dump analysis confirms 0x36da8 holds this value.
                else if (splore_page == 2) {
                    navstate |= 0x08; // S
                }
                // Console Check
                // Fallback: If not Game, Editor, or Splore, it must be Console.
                else {
                    navstate |= 0x10; // C
                }
            }
            
            // Devkit Flag: Only if Game is Active (State 27 or IsGame Flag)
            // This prevents "D" from sticking when exiting to Splore/Console.
            bool is_ingame_active = (state_enum == 27 || picoram[PICORAM_INDEX_ISINGAME]);
            if (is_ingame_active && (picoram[PICORAM_INDEX_DEVKIT] & 0x1)) {
                navstate |= 0x04;
            }
        }
        
        // Write Metadata
        packet_buffer[HEADER_SIZE] = navstate;
        // We reuse the last 4 bytes of the magic string "PICO8SYNC__"
        // New Format: "PICO8SY" (7 bytes) + State(1) + Input(1) + Cart(1) + Editor(1) + NavState(1)
        //memcpy(packet_buffer, "PICO8SY", 7);
        //packet_buffer[7] = state_enum;
        //packet_buffer[8] = input_mode;
        //packet_buffer[9] = cart_loaded;
        //packet_buffer[10] = is_editor;
        //packet_buffer[11] = navstate;
        
        // Write Pixels
        // Convert SDL Surface (RGB888) to Godot (RGBA8888)
        uint32_t* dst32 = (uint32_t*)(packet_buffer + HEADER_SIZE + META_SIZE); 
        const uint32_t* src32 = (uint32_t*)currentsurf->pixels;
        
        // Safety check
        if (src32) {
             for (int i = 0; i < 16384; i++) {
                uint32_t pixel = src32[i];
                // RGB to ABGR (or whatever Godot needs, this was working before)
                *dst32++ = ((pixel & 0x00FF0000) >> 16) | 
                            (pixel & 0x0000FF00)         | 
                            ((pixel & 0x000000FF) << 16) | 
                            0xFF000000;
             }
        } else {
             memset(dst32, 0, PIXEL_SIZE);
        }
        
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
        // printf("event %d\n", event->type);
        if (event->type == SDL_WINDOWEVENT) {
            // printf("blocking\n");
            return 0;
        }
        if (event->type == SDL_KEYDOWN || event->type == SDL_KEYUP) {
            event->key.keysym.sym = 0;
            if (event->key.keysym.scancode == SDLK_LCTRL) {
                event->key.keysym.mod = 0;
            }
        }
    } else {
        int result = pico_poll_event();
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
                    
                    // 'D' key = Scancode 7
                    // if (in_packet[1] == 7 && in_packet[2] == 1) { 
                    //     static int snapcount;
                    //     snapcount++;
                    //     
                    //     printf("Dumping RAM (Targeting 0x37000) to /home/public/...\n");
                    //     
                    //     for (int i = 0; i < candidate_count; i++) {
                    //         // Only dump the one that matches the expected RAM size (225280 bytes)
                    //         // or close to it, just in case.
                    //         // The user confirmed 0x37000 (225280) is the one.
                    //         if (candidates[i].size == 0x37000) {
                    //             char fname[128];
                    //             sprintf(fname, "/home/public/dump_%03d_size_37000.dat", snapcount);
                    //             
                    //             FILE *file = fopen(fname, "wb");
                    //             if (!file) {
                    //                 printf("Failed to open file: %s\n", fname);
                    //             } else {
                    //                 fwrite(candidates[i].ptr, 1, candidates[i].size, file);
                    //                 printf("Dumped RAM to %s\n", fname);
                    //                 fclose(file);
                    //             }
                    //             break; // Found it, done.
                    //         }
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
    
    // PICO-8 0.2.7 RAM allocation size: 0x37000 (225280 bytes)
    if (__c == 0 && __n == 0x37000) {
        if (picoram == NULL) {
             picoram = __s;
             picoram_size = __n;
             printf("SHIM: PICO-8 RAM Locked: %p (Size %zx)\n", picoram, picoram_size);
        }
    }
    return realf(__s, __c, __n);
}