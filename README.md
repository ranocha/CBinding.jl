# CBinding.jl

[![Build Status](https://github.com/analytech-solutions/CBinding.jl/workflows/CI/badge.svg)](https://github.com/analytech-solutions/CBinding.jl/actions)

Use CBinding.jl to automatically create C library bindings with Julia at runtime!

Package supports C features:

- [x] fully supports C's `struct`, `union`, and `enum` types
- [x] alignment strategies
- [x] bit fields
- [x] nested types
- [x] anonymous types
- [x] type qualifiers
- [x] variadic functions
- [x] unknown-length arrays
- [ ] inline functions (todo)
- [x] typed function pointers
- [x] function calling conventions
- [x] automatic callback function pointers
- [x] documentation generation
- [ ] macros (work-in-progress)
- [x] fully supports insane C (i.e. `extern struct { int i; } g[2], func();`)

Read on to learn how to automatically create C library bindings, or [learn how to use the generated bindings](#using-cjl-generated-bindings).


# Create bindings with `CBinding.jl`

First, set up a compiler context to collect C expressions (at the module scope, or at the REPL).

```jl
julia> using CBinding

julia> c``
```

Notice that ``` c`...` ``` is a command macro (with the backticks) and is the means of specifying command line arguments to the Clang parser.
Each time such a command macro is used, a new compiler context is started for the module creating it.
A more real-life example might look like:

```jl
julia> libpath = find_libpath();

julia> c`-std=c99 -Wall -DGO_FAST=1 -Imylib/include -L$(libpath) -lmylib`
```

The compiler context also finds the paths of all specified libraries so it can use them in any bindings that are created.

Next the `c"..."` string macro can be used to input C code and automatically create the equivalent Julia types, global variable bindings, and function bindings.
It is often the case that the C code will span multiple lines, so the triple-quoted variant (`c"""..."""`) is most effective for this usage.

```jl
julia> c"""
         struct S;
         struct T {
           int i;
           struct S *s;
           struct T *t;
         };
         
         extern void func(struct S *s, struct T t);
       """;
```

That's it...
That's all that is needed to create a couple C types and a function binding in Julia, but actually, it gets even easier!

C API's usually come with header files, so let's just use those to create the Julia bindings and save some effort.
By default, bindings are generated from the code directly written in C string macros and header files explicitly included in them, but not headers included by those headers.
[See the `i` string macro option](#options-for-c)) to allow parsing certain implicitly included headers as well.

```jl
julia> c"""
         #include <mylib/header.h>
       """;
```

- [x] all C types are defined in Julia
- [x] C function and global variable bindings defined
- [x] the C API is documented and exported by the enclosing module

All done in just a few lines of code!
[Take a look at the complete example below](#a-complete-example) or continue reading to learn about some more details.


## Some gory details

The C expressions are parsed and immediately converted to Julia code.
In fact, the generated Julia code can be inspected using `@macroexpand`, like this:

```jl
julia> @macroexpand c"""
         struct S;
         struct T {
           int i;
           struct S *s;
           struct T *t;
         };
         
         extern void func(struct S *s, struct T t);
       """
  ⋮
YIKES!
  ⋮
```

In order to support the fully automatic conversion and avoid name collisions, the names of C types or functions are mangled a bit to work in Julia.
Therefore everything generated by CBinding.jl can be accessed with the `c"..."` string macro ([more about this below](#using-cjl-generated-bindings)) to indicate that it lives in C-land.
As an example, the function `func` above is available in Julia as `c"func"`.
It is possible to store the generated bindings to more user-friendly names (this can sometimes be automated, [see the `j` option](#options-for-c)).
Placing each C declaration in its own macro helps when doing this manually, like:

```jl
julia> const S = c"""
         struct S;
       """;

julia> const T = c"""
         struct T {
           int i;
           struct S *s;
           struct T *t;
         };
       """;

julia> c"""
         extern void func(struct S *s, struct T t);
       """j;
```

Constructs from the standard C library headers are currently not being emitted by CBinding.jl, but other packages may be developed to provide a unified source for them.
For now, dependencies on C library or other libraries should be placed before any C code blocks referencing them.
Most often it is only a few `using` and `const` statements.


## A complete example

Finally, an example of what a package using CBinding.jl might look like:

```jl
module LibFoo
  module libfoo
    import Foo_jll
    using CBinding
    
    # libfoo has libbar as a dep, and LibBar has bindings for it
    using LibBar: libbar
    
    # set up the parser
    let
      incdir = joinpath(Foo_jll.artifact_dir, "include")
      libdir = dirname(Foo_jll.libfoo_path)
      
      c`-std=c99 -fparse-all-comments -I$(incdir) -L$(libdir) -lfoo`
    end
    
    # libfoo refers to some std C sized types (eventually made available with something like `using C99`)
    const c"int32_t"  = Int32
    const c"int64_t"  = Int64
    const c"uint32_t" = UInt32
    const c"uint64_t" = UInt64
    
    # generate bindings for libfoo
    c"""
      #include <libfoo/header-1.h>
      #include <libfoo/header-2.h>
    """
    
    # any other bindings not in headers
    c"""
      struct FooStruct {
        struct BarStruct bs;
      };
      
      extern struct FooStruct *foo_like_its_the_80s(int i);
    """
  end
  
  
  # high-level Julian interface to libfoo
  using CBinding
  using .libfoo
  
  function foo(i)
    ptr = c"foo_like_its_the_80s"(Cint(i-1))
    try
      return JulianFoo(ptr[])
    finally
      Libc.free(ptr)
    end
  end
end
```


## Options for `c"..."`

The string macro has some options to handle more complex use cases.
Occasionally it is necessary to include or define C code that is just a dependency and should not be exported or perhaps excluded from the generated bindings altogether.
These kinds of situations can be handled with combinations of the following string macro suffixes.

- `d` - defer conversion of the C code block; successive blocks marked with `d` will keep deferring until a block without it (its options will be used for processing the deferred blocks)
- `i` - also parse implicitly included headers that are related (in the same directory or subdirectories of it) to explicitly included headers
- `j` - also define bindings with Julian names (name collisions likely)
- `p` - mark the C code as "private" content that will not be exported
- `q` - quietly parse the block of C code, suppressing any compiler messages
- `r` - the C code is only a reference to something in C-land and bindings are not to be generated
- `s` - skip creating bindings for this block of C code
- `u` - leave this block of C code undocumented

```jl
julia> c"""
         #include <stdio.h>  // provides FILE type, but skip emitting bindings for this block
       """s;

julia> c"""
         struct File {  // do not include this type in module exports, and suppress compiler messages
          FILE *f;
         };
       """pq;
```


# Using `CBinding.jl`-generated bindings

The `c"..."` string macro can be used to refer to any of the types, global variables, or functions generated by CBinding.jl.
When simply referencing the C content, setting up a compiler context (i.e. using ``` c`...` ```) is not necessary.

The `c"..."` string macro can take on two meanings depending on the content placed in it.
So to guarantee it is interpreted as a reference to something in C, rather than a block of C code to create bindings with, include an `r` in the string macro options.

```jl
julia> module MyLib  # generally some C bindings are defined elsewhere
         using CBinding
         
         c`-std=c99 -Wall -Imy/include`
         
         c"""
           struct S;
           struct T {
             int i;
             struct S *s;
             struct T *t;
           };
           
           extern void func(struct S *s, struct T t);
         """
       end

julia> using CBinding, .MyLib

julia> c"struct T" <: Cstruct
true

julia> c"struct T"r <: Cstruct  # use 'r' option to guarantee it is treated as a reference
true

julia> t = c"struct T"(i = 123);

julia> t.i
123
```

The user-defined types (`enum`, `struct`, and `union`) are referenced just as they are in C (e.g. `c"enum E"`, `c"struct S"`, and `c"union U"`).
All other types, pointers, arrays, global variables, enumeration constants, functions, etc. are also referenced just as they are in C.
Here is a quick reference for C string macro usage:

- `c"int"` - the `Cint` type
- `c"int[2]"` - a length-2 static array `Cint`'s
- `c"int[2][4]"` - a length-2 static array of length-4 static arrays of `Cint`'s
- `c"int *"` - pointer to a `Cint`
- `c"int **"` - pointer to a pointer to a `Cint`
- `c"int const **"` - pointer to a pointer to a read-only `Cint`
- `c"enum MyUnion"` - a user-defined C `enum` type
- `c"union MyUnion"` - a user-defined C `union` type
- `c"struct MyStruct"` - a user-defined C `struct` type
- `c"struct MyStruct *"` - a pointer to a user-defined C `struct` type
- `c"struct MyStruct [2]"` - a length-2 static array of user-defined C `struct` type
- `c"MyStruct"` - a user-defined `typedef`-ed type
- `c"MyStruct *"` - a pointer to a user-defined `typedef`-ed type
- `c"printf"` - the printf function
- `c"int (*)(int, int)"` - a function pointer
- `c"int (*)(char const *, ...)"` - a variadic function pointer

The following examples demonstrate how to refer to C-land content that resides in other modules and is not exported/imported:

- `c"SomeModule.SubModule.enum MyUnion"`
- `c"SomeModule.SubModule.struct MyStruct *"`
- `c"SomeModule.SubModule.printf"`
- `c"int (*)(Some.Other.Module.struct MyStruct *, ...)"`

The C string macro can also be used to expose Julia content to C-land.

```jl
julia> const c"IntPtr" = Cptr{Cint};

julia> c"void (*)(IntPtr, IntPtr *, IntPtr[2])" <: Cptr{<:Cfunction}
true
```

Type qualifiers are carried over from the C code.
As an example, `int const *` is a pointer to a read-only integer in is represented by CBinding.jl as the type `Cptr{Cconst{Cint}}`.
The `unqualifiedtype(T)` can be used to strip away the type qualifiers to get to the core type, so `unqualifiedtype(Cconst{Cint}) === Cint`.

[As mentioned above](#any-gotchas), the `bitstype(T)` function can be used to acquire the concrete bits type of user-defined C types as well.


## Working with aggregate types and sized arrays

User-defined aggregate types (`struct` and `union`) have several ways to be constructed:

- `t = c"struct T"()` - zero-ed immutable object
- `t = c"struct T"(i = 123)` - zero-ed immutable object with field `i` initialized to 123
- `t = c"struct T"(t, i = 321)` - copy of `t` with field `i` initialized to 321

These objects are immutable and changing fields will have no effect, so a copy must be constructed with the desired field overrides or ((pointers must be used)[#working-with-pointers]).
Nested field access is transparent, and performance should match that of accessing fields within standard Julia immutable structs.

Statically-sized arrays (i.e. `c"typedef int IntArray[4];"`) can be constructed:

- `t = c"IntArray"()` - zero-ed immutable array
- `t = c"IntArray"(1, 2)` - zero-ed immutable array with first 2 elements initialized to 1 and 2
- `t = c"IntArray"(t, 3)` - copy of `t` with first element initialized to 3
- `t = c"IntArray"(t, 4 => 123)` - copy of `t` with 4th element initialized to 123

Constructors for both aggregates and arrays can also accept nested `Tuple` and `NamedTuple` arguments which get splatted appropriately into the respective field's constructor.
A comprehensive example of constructing a complex C type and accessing fields/elements is shown below:

```jl
julia> c`` ; c"""
         struct A {
           struct {
             int i;
           };
           struct {
             struct {
               int i;
             } c[2];
           } b;
         };
       """;

julia> a = c"struct A"();

julia> a.i
0

julia> a.b.c[2].i
0

julia> a = c"struct A"(i = 123, b = (c = ((i = 321,), (i = 654,)),));

julia> a.i
123

julia> a.b.c[2].i
654

```


## Working with pointers

CBinding.jl also works elegantly with pointers to aggregate types.
Pointers are followed through fields and array elements as they are accessed, and they can be dereferenced with `ptr[]` or written to with `ptr[] = val`.

```jl
julia> ptr = Libc.malloc(a);  # allocate a `struct A` as a copy of `a`

julia> ptr.i
Cptr{Int32}(0x0000000003458810)

julia> ptr.i[]
123

julia> ptr.b.c[2].i
Cptr{Int32}(0x0000000003458814)

julia> ptr.b.c[2].i[]
654

julia> ptr.b.c[2].i[] = 42
42

julia> Libc.free(ptr)  # deallocate it
```

An exception to the rule is bitfields.
It is not possible to refer to bitfields with a pointer, so access to bitfields is automatically dereferenced.


## Using global variable and function bindings

Bindings to global variables also behave as if they are pointers, and must be dereferenced to be read or written, but any fields and elements can be followed through with pointers.
Bindings to functions are direct, but getting the pointer to a bound function can be done with the `func[]` syntax.

```jl
julia> c"func"(Cint(1), Cint(2));  # call the C function directly

julia> funcptr = c"func"[]
Cptr{Cfunction{Int32, Tuple{Int32, Int32}, :cdecl}}(0x00007f8f50722b10)

julia> funcptr(Cint(1), Cint(2));  # call the C function pointer
```


## Using Julia functions in C

Providing a Julia method to C as a callback function has never been easier!
Just pass it as an argument to the CBinding.jl function binding or function pointer.
Assuming a binding to a C function, like `void set_callback(int (*cb)(int, int))` exists:

```jl
julia> function myadd(a, b)  # a callback function to give to C
         return a+b
       end;

julia> c"set_callback"(myadd)  # that's it!

julia> function saferadd(a::Cint, b::Cint)::Cint  # a safer callback function might require type paranoia
         return a+b
       end;

julia> c"set_callback"(saferadd)
```


# Any gotchas?

Inline functions and macros are not yet implemented, but they will be added in future releases.

Since Julia does not yet provide `incomplete type` (please voice your support of the feature here: https://github.com/JuliaLang/julia/issues/269), abstract types are used to allow forward declarations in C.
Therefore, referencing C types usually refers to the abstract type which can have significant implications when creating Julia arrays, using `ccall`, etc.
The following example illustrates this kind of unexpected behavior:

```jl
julia> struct X
         i::Cint
       end

julia> const Y = c"""
         struct Y {
           int i;
         };
       """

julia> [X(123)] isa Vector{X}
true

julia> [Y(i=123)] isa Vector{Y}
false

julia> [Y(i=123)] isa Vector{bitstype(Y)}
true

```

The `bitstype(T)` function can be used to acquire the concrete bits type of any C type when the distinction matters.

Another implementation detail worth noting is that function bindings are brought into Julia as singleton constants, not as actual functions.
This approach allows a user to obtain function pointers from C functions in case one must be used as a callback function.
Therefore, attaching other methods to a bound C function is not possible.

It is also sometimes necessary to use the `c"..."` mangled names directly in Julia (for instance in the REPL help mode).
Until consistent, universal support for the string macro is available, the mangled names can be used directly as `var"c\"...\""`, like `help?> var"c\"struct Y\""`.

