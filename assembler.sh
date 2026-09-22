#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Error: expected exactly one .vsc file."
    exit 1
fi

input_file="$1"

if [ ! -f "$input_file" ]; then
    echo "Error: file does not exist or is not a regular file."
    exit 1
fi

if [[ "$input_file" != *.vsc ]]; then
    echo "Error: input file must have .vsc extension."
    exit 1
fi

if [ ! -s "$input_file" ]; then
    echo "Error: input file is empty."
    exit 1
fi

dataArray=()
lines=()

while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    lines+=("$line")
done < "$input_file"

if [ "${#lines[@]}" -eq 0 ]; then
    echo "Error: input file contains no valid lines."
    exit 1
fi

first_line="${lines[0]}"
program_type=""

if [ "$first_line" -eq 0 ]; then
    program_type="QUIT"

    if [ "${#lines[@]}" -lt 2 ]; then
        echo "Error: missing QUIT instruction."
        exit 1
    fi

    if [ "${lines[1]}" != "QUIT,0,0" ]; then
        echo "Error: line 2 must be exactly QUIT,0,0."
        exit 1
    fi

    dataArray+=("20")
    dataArray+=("00")

    if [ "${#lines[@]}" -gt 2 ]; then
        echo "Error: extra instructions after QUIT,0,0."
        exit 1
    fi
    
    start_index=2 

elif [ "$first_line" -eq 2 ]; then
    program_type="ADD/SUB"

    if [ "${#lines[@]}" -lt 3 ]; then
        echo "Error: line 2 and line 3 must contain integers."
        exit 1
    fi

    for ((i=1; i<=2; i++)); do
        value="${lines[$i]}"

        if [[ ! "$value" =~ ^[0-9]+$ ]]; then
            echo "Error: line $((i+1)) must be an integer."
            exit 1
        fi

        if [ "$value" -lt 0 ] || [ "$value" -ge 128 ]; then
            echo "Error: value on line $((i+1)) must be in range [0,128)."
            exit 1
        fi

        dataArray+=("$(printf '%02x' "$value")")
    done

    start_index=3

else
    echo "Error: line 1 must be either 0 or 2."
    exit 1
fi

instruction_count=0
quit_found=0

for ((i=start_index; i<${#lines[@]}; i++)); do
    line="${lines[$i]}"

    if [ "${#line}" -gt 11 ]; then
        echo "Error: instruction on line $((i+1)) is too long."
        exit 1
    fi

    IFS=',' read -r mnem reg mem extra <<< "$line"

    if [ -n "$extra" ] || [ -z "$mnem" ] || [ -z "$reg" ] || [ -z "$mem" ]; then
        echo "Error: invalid instruction format on line $((i+1))."
        exit 1
    fi

    case "$mnem" in
        LOAD)  op=1 ;;
        STORE) op=2 ;;
        ADD)   op=3 ;;
        SUB)   op=4 ;;
        QUIT)  op=8 ;;
        PRINT) op=9 ;;
        *)
            echo "Error: invalid instruction '$mnem' on line $((i+1))."
            exit 1
            ;;
    esac

    if [[ ! "$reg" =~ ^[0-9]+$ ]]; then
        echo "Error: register must be an integer on line $((i+1))."
        exit 1
    fi

    if [ "$reg" -lt 0 ] || [ "$reg" -gt 3 ]; then
        echo "Error: register must be between 0 and 3 on line $((i+1))."
        exit 1
    fi

    if [[ ! "$mem" =~ ^[0-9]+$ ]]; then
        echo "Error: memory address must be an integer on line $((i+1))."
        exit 1
    fi

    if [ "$mem" -lt 0 ] || [ "$mem" -gt 255 ]; then
        echo "Error: memory address must be between 0 and 255 on line $((i+1))."
        exit 1
    fi

    byte1=$(( (op << 2) | reg ))
    byte1_hex=$(printf '%02x' "$byte1")
    byte2_hex=$(printf '%02x' "$mem")

    dataArray+=("$byte1_hex")
    dataArray+=("$byte2_hex")

    if [ "$mnem" = "QUIT" ] && [ "$reg" -eq 0 ] && [ "$mem" -eq 0 ]; then
        quit_found=1
        break
    fi

    instruction_count=$((instruction_count + 1))

    if [ "$instruction_count" -gt 100 ]; then
        echo "Error: maximum of 100 instructions exceeded."
        exit 1
    fi
done

if [ "$first_line" -eq 2 ] && [ "$quit_found" -eq 0 ]; then
    echo "Error: program must end with QUIT,0,0."
    exit 1
fi

outfile="${input_file%.vsc}.bin"
rm -f "$outfile"

for byte in "${dataArray[@]}"; do
    printf "\x$byte" >> "$outfile"
done

if [ "$program_type" = "QUIT" ]; then
    echo "It is a QUIT program"
else
    echo "It is an ADD/SUB program"
fi

for byte in "${dataArray[@]}"; do
    echo "$byte"
done
