FILE="${1:-}"

if [ ! -f "$FILE" ]; then
    echo "No such file" 
    exit 1
fi

inotifywait -m -e modify "$FILE" | while read; do
  tail -n 5 "$FILE"
done
