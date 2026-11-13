FROM livecodesvip/php-runtime:latest

USER root

# 1. 在刪除舊版 PHP 前，先提取原本所有的 PHP 模組列表（排除內建核心與標題行），並根據原清單精準安裝對應的 PHP 8.3 模組
RUN apk update && \
    OLD_MODULES=$(/opt/php/bin/php -m | grep -vE '^\[|^(Core|date|filter|hash|json|libxml|openssl|pcre|Reflection|SPL|standard|zlib|mysqlnd|Zend OPcache)$' | tr '[:upper:]' '[:lower:]') && \
    echo "檢測到原有擴充清單: $OLD_MODULES" && \
    PKGS="php83 php83-cli php83-fpm php83-phar php83-openssl php83-json php83-opcache" && \
    for mod in $OLD_MODULES; do \
        if apk search -x "php83-$mod" | grep -q "php83-$mod"; then \
            PKGS="$PKGS php83-$mod"; \
        elif apk search -x "php83-pecl-$mod" | grep -q "php83-pecl-$mod"; then \
            PKGS="$PKGS php83-pecl-$mod"; \
        else \
            echo "⚠️ 提示: 模組 $mod 為內建或倉庫中無獨立套件，已跳過"; \
        fi; \
    done && \
    echo "即將安裝的精準套件: $PKGS" && \
    apk add --no-cache $PKGS && \
    rm -rf /var/cache/apk/*

# 2. 移除舊版 PHP 7.4 執行檔，並將路徑軟連結至新的 PHP 8.3
RUN rm -rf /opt/php/bin/php /opt/php/sbin/php-fpm && \
    mkdir -p /opt/php/bin /opt/php/sbin && \
    ln -sf /usr/bin/php83 /opt/php/bin/php && \
    ln -sf /usr/bin/php83 /usr/bin/php && \
    if [ -f /usr/sbin/php-fpm83 ]; then ln -sf /usr/sbin/php-fpm83 /opt/php/sbin/php-fpm; fi

# 3. 驗證版本與最終模組清單
RUN php -v && php -m
