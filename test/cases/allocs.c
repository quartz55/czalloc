#include <stdio.h>
#include <stdlib.h>

extern void checkLeaks();

int main() {
  auto size = 100U;
  int *arr = malloc(size * sizeof(int)); // Uses Zig allocator
  if (!arr) {
    if (fprintf(stderr, "Allocation failed!\n") < 0) {
      perror("fprintf failed");
    }
    return 1;
  }
  arr[0] = 42;
  printf("Allocated: %d\n", arr[0]);

  int *new_arr = realloc(arr, 200 * sizeof(int)); // Resize safely
  free(new_arr); // Correctly freed via Zig's allocator

  void *ptr;
  auto const alignment = 64U;
  // Allocate 64B-aligned memory for AVX-512
  if (posix_memalign(&ptr, alignment, 1024) != 0) {
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
