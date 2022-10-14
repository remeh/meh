#!/bin/bash

for file in $(rg -l "test \"" src);
do
    echo Running tests in ${file}:
    zig test ${file}
done;
