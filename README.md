SubvertGL
=========

A simple OpenGL function redirector and argument logger with near 0 dependencies.

I had a need to debug the output of a network driven OpenGL program that ran on a highly customized linux server OS. The common tools for debugging OpenGL require you to launch the target program as a child of another. Some of them have significant dependencies that my custom OS install lacked. At the end of the day, I wrote this script to overload the OpenGL calls of my application so I could force all glColorX( calls to set the output to white.

I hope you find this useful.

Usage
=====
The version of GL/gl.h may be different than mine. You will need to generate a custom override file
using the subvert_gl.pl script.

You can build the output into a shared library and use it to overload the OpenGL calls your program uses.
````
perl subvert_gl.pl
gcc -o libGlOverride.so -shared -fPIC gloverride.o
LD_PRELOAD=libGlOverride.so ./yourprogram
````
Note: You would need to add the following lines to your application for this to work.
````
extern void mb_init_gl();

//...

int main (/* ... */)
{
    mb_init_gl();
    // code that makes glcalls
}
````


You can also simply compile the output into a .o and include it directly into your application.
````
perl subvert_gl.pl
gcc -c gloverride.o
gcc -o yourprogram yoursource.c gloverride.o
````

When your program runs, the OpenGL calls will have their non-pointer arguments displayed to stderr as double precision decimal numbers. Some conversion may be necessary to determine what GL_ define is being passed in.
