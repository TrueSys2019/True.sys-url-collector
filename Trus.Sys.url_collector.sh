# Creating the file while preventing any formatting issues
cat > Trus.Sys.url_collector.sh << 'EOF'
#!/bin/bash

# --- Automatic Formatting Fix ---
fix_formatting() {
    if grep -q -U $'\x0D' "$0"; then
        echo -e "\n[+] Detected a formatting issue. Fixing..."
        sed -i 's/\r$//' "$0"
        exec "$0" "$@"
        exit $?
    fi
}
fix_formatting "$@"

# --- Installing Essential Dependencies ---
install_dependencies() {
    echo -e "\n[+] Checking essential dependencies..."
    
    for pkg in git golang python3 python3-pip; do
        if ! command -v "$pkg" &>/dev/null; then
            echo "[!] $pkg is not installed. Installing..."
            sudo apt-get install -y "$pkg" || { echo "❌ Failed to install $pkg"; exit 1; }
        else
            echo "[✓] $pkg is already installed."
        fi
    done

    echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
    source ~/.bashrc
}

# --- Installing Required Tools ---
install_tools() {
    echo -e "\n[+] Checking installed tools..."

    declare -A tools=(
        ["gau"]="go install github.com/lc/gau/v2/cmd/gau@latest"
        ["waybackurls"]="go install github.com/tomnomnom/waybackurls@latest"
        ["katana"]="go install github.com/projectdiscovery/katana/cmd/katana@latest"
        ["gospider"]="go install github.com/jaeles-project/gospider@latest"
        ["httpx"]="go install github.com/projectdiscovery/httpx/cmd/httpx@latest"
        ["arjun"]="pip3 install arjun"
    )

    for tool in "${!tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo "[!] Installing $tool..."
            eval "${tools[$tool]}" || { echo "❌ Failed to install $tool"; exit 1; }
        else
            echo "[✓] $tool is already installed."
        fi
    done

    # Installing ParamSpider
    if [ ! -d "ParamSpider" ]; then
        echo "[!] Installing ParamSpider..."
        git clone https://github.com/devanshbatham/ParamSpider || { echo "❌ Failed to clone ParamSpider"; exit 1; }
        pip3 install -r ParamSpider/requirements.txt || { echo "❌ Failed to install ParamSpider requirements"; exit 1; }
    else
        echo "[✓] ParamSpider is already installed."
    fi
}

# --- Main Function ---
main() {
    if [ -z "$1" ]; then
        echo "🔹 Usage: ./Trus.Sys.url_collector.sh example.com"
        exit 1
    fi

    install_dependencies
    install_tools

    DOMAIN=$1
    OUTPUT_DIR="scan_results_$DOMAIN"
    mkdir -p "$OUTPUT_DIR"

    echo -e "\n[+] Starting URL collection for $DOMAIN ...\n"

    echo "[+] Fetching URLs from Wayback Machine & Common Crawl (gau)..."
    gau "$DOMAIN" | sort -u > "$OUTPUT_DIR/gau_urls.txt"

    echo "[+] Fetching URLs from Wayback Machine only (waybackurls)..."
    echo "$DOMAIN" | waybackurls | sort -u > "$OUTPUT_DIR/wayback_urls.txt"

    echo "[+] Crawling with Katana..."
    katana -u "https://$DOMAIN" -depth 3 -jc -kf -o "$OUTPUT_DIR/katana_urls.txt"

    echo "[+] Crawling with GoSpider..."
    gospider -s "https://$DOMAIN" -d 2 --js --other-source --subs -o "$OUTPUT_DIR/gospider" -c 10 -t 20

    echo "[+] Merging and filtering URLs..."
    cat "$OUTPUT_DIR"/gau_urls.txt "$OUTPUT_DIR"/wayback_urls.txt "$OUTPUT_DIR"/katana_urls.txt "$OUTPUT_DIR"/gospider/* | sort -u > "$OUTPUT_DIR/all_urls.txt"

    echo "[+] Checking live URLs (httpx)..."
    cat "$OUTPUT_DIR/all_urls.txt" | httpx -status-code -title -tech-detect -o "$OUTPUT_DIR/live_urls.txt"

    echo "[+] Extracting parameters (ParamSpider)..."
    python3 ParamSpider/paramspider.py -d "$DOMAIN" --output "$OUTPUT_DIR/param_urls.txt"

    echo "[+] Finding hidden parameters (Arjun)..."
    arjun -i "$OUTPUT_DIR/live_urls.txt" -o "$OUTPUT_DIR/arjun_params.json"

    echo -e "\n[✔] Scan completed! Results saved in: $OUTPUT_DIR"
}

main "$@"
EOF

# Making the script executable
chmod +x Trus.Sys.url_collector.sh
echo "[✔] Trus.Sys.url_collector.sh has been created and made executable!"
