# إنشاء الملف مع منع أي مشاكل في التنسيق
cat > url_collector.sh << 'EOF'
#!/bin/bash

# --- إصلاح تلقائي لمشاكل التنسيق ---
fix_formatting() {
    if grep -q -U $'\x0D' "$0"; then
        echo -e "\n[+] اكتشاف مشكلة في تنسيق الملف. جاري الإصلاح..."
        sed -i 's/\r$//' "$0"
        exec "$0" "$@"
        exit $?
    fi
}
fix_formatting "$@"

# --- تثبيت المتطلبات الأساسية ---
install_dependencies() {
    echo -e "\n[+] التحقق من المتطلبات الأساسية..."
    
    for pkg in git golang python3 python3-pip; do
        if ! command -v "$pkg" &>/dev/null; then
            echo "[!] $pkg غير مثبت. جاري التثبيت..."
            sudo apt-get install -y "$pkg" || { echo "❌ فشل تثبيت $pkg"; exit 1; }
        else
            echo "[✓] $pkg مثبت بالفعل."
        fi
    done

    echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
    source ~/.bashrc
}

# --- تثبيت الأدوات المطلوبة ---
install_tools() {
    echo -e "\n[+] التحقق من الأدوات المثبتة..."

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
            echo "[!] تثبيت $tool ..."
            eval "${tools[$tool]}" || { echo "❌ فشل تثبيت $tool"; exit 1; }
        else
            echo "[✓] $tool مثبت بالفعل."
        fi
    done

    # تثبيت ParamSpider
    if [ ! -d "ParamSpider" ]; then
        echo "[!] تثبيت ParamSpider ..."
        git clone https://github.com/devanshbatham/ParamSpider || { echo "❌ فشل تحميل ParamSpider"; exit 1; }
        pip3 install -r ParamSpider/requirements.txt || { echo "❌ فشل تثبيت متطلبات ParamSpider"; exit 1; }
    else
        echo "[✓] ParamSpider مثبت بالفعل."
    fi
}

# --- الوظيفة الرئيسية ---
main() {
    if [ -z "$1" ]; then
        echo "🔹 طريقة الاستخدام: ./url_collector.sh example.com"
        exit 1
    fi

    install_dependencies
    install_tools

    DOMAIN=$1
    OUTPUT_DIR="scan_results_$DOMAIN"
    mkdir -p "$OUTPUT_DIR"

    echo -e "\n[+] بدء جمع الروابط لـ $DOMAIN ...\n"

    echo "[+] جلب الروابط من Wayback Machine & Common Crawl (gau)..."
    gau "$DOMAIN" | sort -u > "$OUTPUT_DIR/gau_urls.txt"

    echo "[+] جلب الروابط من Wayback Machine فقط (waybackurls)..."
    echo "$DOMAIN" | waybackurls | sort -u > "$OUTPUT_DIR/wayback_urls.txt"

    echo "[+] الزحف باستخدام Katana..."
    katana -u "https://$DOMAIN" -depth 3 -jc -kf -o "$OUTPUT_DIR/katana_urls.txt"

    echo "[+] الزحف باستخدام GoSpider..."
    gospider -s "https://$DOMAIN" -d 2 --js --other-source --subs -o "$OUTPUT_DIR/gospider" -c 10 -t 20

    echo "[+] دمج وتصفية الروابط..."
    cat "$OUTPUT_DIR"/gau_urls.txt "$OUTPUT_DIR"/wayback_urls.txt "$OUTPUT_DIR"/katana_urls.txt "$OUTPUT_DIR"/gospider/* | sort -u > "$OUTPUT_DIR/all_urls.txt"

    echo "[+] التحقق من الروابط النشطة (httpx)..."
    cat "$OUTPUT_DIR/all_urls.txt" | httpx -status-code -title -tech-detect -o "$OUTPUT_DIR/live_urls.txt"

    echo "[+] البحث عن باراميترات (ParamSpider)..."
    python3 ParamSpider/paramspider.py -d "$DOMAIN" --output "$OUTPUT_DIR/param_urls.txt"

    echo "[+] البحث عن باراميترات مخفية (Arjun)..."
    arjun -i "$OUTPUT_DIR/live_urls.txt" -o "$OUTPUT_DIR/arjun_params.json"

    echo -e "\n[✔] اكتمل المسح! النتائج محفوظة في: $OUTPUT_DIR"
}

main "$@"
EOF

# جعل السكريبت قابلًا للتنفيذ
chmod +x url_collector.sh
echo "[✔] تم إنشاء url_collector.sh وجعله قابلًا للتشغيل!"
