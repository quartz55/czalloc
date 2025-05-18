#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(__clang__)
#ifdef __clang_analyzer__
/* Suppress security.insecureAPI.DeprecatedOrUnsafeBufferHandling warning
 * https://clang.llvm.org/docs/analyzer/user-docs/FAQ.html#id10
 */
#define NOLINT_UNSAFE_BUFFER_HANDLING [[clang::suppress]]
#else
#define NOLINT_UNSAFE_BUFFER_HANDLING
#endif
#elif defined(__GNUC__)
#define NOLINT_UNSAFE_BUFFER_HANDLING
#else
#define NOLINT_UNSAFE_BUFFER_HANDLING
#endif

extern void checkLeaks();

int main() {
  auto const m_size = 100U * sizeof(uint32_t);
  uint32_t *arr = malloc(m_size); // Uses Zig allocator

  if (!arr) {
    NOLINT_UNSAFE_BUFFER_HANDLING
    if (fprintf(stderr, "Allocation failed!\n") < 0) { // NOLINT
      perror("fprintf failed");
    }
    return 1;
  }
  arr[0] = (uint32_t)m_size;
  printf("Allocated: %ud\n", arr[0]);

  auto const new_size = 200U;
  int *new_arr = realloc(arr, new_size * sizeof(int)); // Resize safely
  free(new_arr); // Correctly freed via Zig's allocator

  void *ptr = nullptr;
  auto const alignment = 64U;
  auto const memalign_size = 1024U;
  // Allocate 64B-aligned memory for AVX-512
  if (posix_memalign(&ptr, alignment, memalign_size) != 0) {
    perror("posix_memalign failed");
    return 1;
  }
  printf("Allocated 64-byte-aligned memory at %p\n", ptr);
  free(ptr);

  // Optional: Call Zig's cleanup (if linked)
  checkLeaks(); // Checks for leaks
  printf("Success!\n");
  return 0;
}
