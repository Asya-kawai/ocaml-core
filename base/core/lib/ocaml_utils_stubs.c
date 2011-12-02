/* Various utility functions for C <-> Caml interoperability. */

#include <string.h>

int strcmp_not_a_macro(const char* s1, const char* s2)
{
  /* See caml_utils_macros.h for why this is needed. */

  return strcmp(s1, s2);
}

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "ocaml_utils.h"
#include "ocaml_utils_macros.h"

/* Exceptions */

void raise_with_two_args(value tag, value arg1, value arg2)
{
  value v_exc;

  Begin_roots3(tag, arg1, arg2);
    v_exc = caml_alloc_small(3, 0);
    Field(v_exc, 0) = tag;
    Field(v_exc, 1) = arg1;
    Field(v_exc, 2) = arg2;
  End_roots();

  caml_raise(v_exc);
}

value* named_value_exn(const char* n)
{
  value* v = caml_named_value(n);
  if (v == NULL)
  {
    char msg[256];
    snprintf(msg, sizeof(msg), "%s not registered.", n);
    caml_failwith(msg);
  }
  return v;
}

void raise_out_of_memory(void)
{
  value* out_of_memory;
  out_of_memory = named_value_exn("Out_of_memory");
  assert(out_of_memory != NULL);  /* [named_value_exn] should ensure this. */
  caml_raise_constant(*out_of_memory);
}

void* malloc_exn(size_t size)
{
  void* ptr = malloc(size);
  if (ptr == NULL) raise_out_of_memory();
  return ptr;
}

const char* string_ocaml_to_c(value s_v)
{
  int length;
  char *s;

  assert(Is_string(s_v));

  length = caml_string_length(s_v);
  s = malloc_exn(length + 1);
  memcpy(s, String_val(s_v), length + 1);

  return s;
}

const char* string_of_ocaml_string_option(value v)
{
  assert(Is_string_option(v));

  if (Is_none(v)) return NULL;
  return string_ocaml_to_c(Field(v, 0));
}

int int_of_ocaml_int_option(value v, int* i)
{
  assert(Is_int_option(v));

  if (Is_some(v)) *i = Long_val(Field(v, 0));
  return Is_none(v) ? 0 : 1;
}

const char** array_map(value array,
                       const char* (*f__must_not_allocate_on_caml_heap)(value))
{
  const char** new_array;
  unsigned int i, length;

  length = Wosize_val(array);
  if (length == 0) return NULL;

  new_array = malloc_exn(sizeof(char*) * length);
  for (i = 0; i < length; i++)
    new_array[i] = f__must_not_allocate_on_caml_heap(Field(array, i));

  return new_array;
}
