FILE="${1:-}"

if [ ! -f "$FILE" ]; then
    echo "No such file" 
    exit 1
fi

watch -n 0.2 "tail -n 5 "$FILE""
