FROM livecodesvip/php-runtime:latest

# 接收外部傳入的 PHP 版本號，預設為 8.3
ARG PHP_VER=8.3

USER root

# 1. 將版本號去掉小數點（例如 8.3 -> 83），並動態匹配原有擴充清單進行安裝
RUN PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    echo "目標 PHP 套件前綴: ${PHP_PKG_PREFIX}" && \
    apk update && \
    OLD_MODULES=$(/opt/php/bin/php -m | grep -vE '^\[|^(Core|date|filter|hash|json|libxml|openssl|pcre|Reflection|SPL|standard|zlib|mysqlnd|Zend OPcache)$' | tr '[:upper:]' '[:lower:]') && \
    PKGS="${PHP_PKG_PREFIX} ${PHP_PKG_PREFIX}-cli ${PHP_PKG_PREFIX}-fpm ${PHP_PKG_PREFIX}-phar ${PHP_PKG_PREFIX}-openssl ${PHP_PKG_PREFIX}-json ${PHP_PKG_PREFIX}-opcache" && \
    for mod in $OLD_MODULES; do \
        if apk search -x "${PHP_PKG_PREFIX}-$mod" | grep -q "${PHP_PKG_PREFIX}-$mod"; then \
            PKGS="$PKGS ${PHP_PKG_PREFIX}-$mod"; \
        elif apk search -x "${PHP_PKG_PREFIX}-pecl-$mod" | grep -q "${PHP_PKG_PREFIX}-pecl-$mod"; then \
            PKGS="$PKGS ${PHP_PKG_PREFIX}-pecl-$mod"; \
        else \
            echo "⚠️ 提示: 模組 $mod 為內建或倉庫中無獨立套件，已跳過"; \
        fi; \
    done && \
    echo "即將安裝的精準套件: $PKGS" && \
    apk add --no-cache $PKGS && \
    rm -rf /var/cache/apk/*

# 2. 移除舊版 PHP 7.4 執行檔，並建立軟連結指向新版本
RUN PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    rm -rf /opt/php/bin/php /opt/php/sbin/php-fpm && \
    mkdir -p /opt/php/bin /opt/php/sbin && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /opt/php/bin/php && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /usr/bin/php && \
    if [ -f /usr/sbin/php-fpm$(echo ${PHP_VER} | tr -d '.') ]; then \
        ln -sf /usr/sbin/php-fpm$(echo ${PHP_VER} | tr -d '.') /opt/php/sbin/php-fpm; \
    fi

# 3. 驗證版本與模組
RUN php -v && php -m
