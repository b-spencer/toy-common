# Common pieces shared by my toy projects

This is a tiny build system using GNU Make.  It supports optional Google
Benchmark speed tests and Boost UT unit tests.

This is not production grade.  It's meant for playing around with C++ projects
that are one or a few source files, just for fun.

# Barely Sufficient Instructions

To use this, make it a submodule of your project.  I put it in the `common/` directory of the root.
Then put your code in another subdirectory.  (It just makes life easier that way because this thing is very primitive.)

    mkdir project/
    cd project/
    git init .
    git submodule add https://github.com/b-spencer/toy-common.git common
    echo "include common/mk/common.mk" >Makefile
    (echo /bin/; echo /obj/; echo /prog) >.gitignore
    mkdir src/
    cd src/
    echo '#include <iostream>' > main.cc
    echo 'int main() { std::cout << "Hello, world!\n"; }' >> main.cc
    make
    ./prog
    
To debug:

    make clean
    DEBUG=1 make
    gdb prog
    
To test, but Boost UT files in test/\*.cc and then:

    make tests
    
To benchmark, put Google Benchmark files in bench/\*.cc and then:

    make bench

It barely works.  Cut it some slack. :)
