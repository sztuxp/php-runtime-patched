FROM livecodesvip/php-runtime:latest

# 接收外部傳入的目標 PHP 版本號（用來替換原本的 7.4 槽位），預設為 8.3
ARG PHP_VER=8.3

USER root

# 1. 升級原系統的 PHP 8.4 至最新版本，並安裝你指定的目標 PHP 版本（維持原插件）
RUN PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    apk update && \
    # 1a. 先提取原本 7.4 的模組清單（必須在刪除 7.4 前提取） \
    OLD_MODULES=$(/opt/php/bin/php -m | grep -vE '^\[|^(Core|date|filter|hash|json|libxml|openssl|pcre|Reflection|SPL|standard|zlib|mysqlnd|Zend OPcache)$' | tr '[:upper:]' '[:lower:]') && \
    # 1b. 升級系統原生的 PHP 8.4 及其所有已安裝擴充套件至最新安全版本，並升級底層 OpenSSL 庫 \
    apk upgrade --no-cache $(apk info | grep -E '^php84|^libssl|^libcrypto') && \
    # 1c. 若指定的目標版本不是 8.4，則精準安裝對應版本的 PHP 與原模組 \
    if [ "${PHP_PKG_PREFIX}" != "php84" ]; then \
        PKGS="${PHP_PKG_PREFIX} ${PHP_PKG_PREFIX}-cli ${PHP_PKG_PREFIX}-fpm ${PHP_PKG_PREFIX}-phar ${PHP_PKG_PREFIX}-openssl ${PHP_PKG_PREFIX}-json ${PHP_PKG_PREFIX}-opcache" && \
        for mod in $OLD_MODULES; do \
            if apk search -x "${PHP_PKG_PREFIX}-$mod" | grep -q "${PHP_PKG_PREFIX}-$mod"; then \
                PKGS="$PKGS ${PHP_PKG_PREFIX}-$mod"; \
            elif apk search -x "${PHP_PKG_PREFIX}-pecl-$mod" | grep -q "${PHP_PKG_PREFIX}-pecl-$mod"; then \
                PKGS="$PKGS ${PHP_PKG_PREFIX}-pecl-$mod"; \
            fi; \
        done && \
        apk add --no-cache $PKGS; \
    fi && \
    rm -rf /var/cache/apk/*

# 2. 清理舊版 PHP 7.4 二進位殘留，並建立軟連結將 /opt/php 指向新指定的 PHP 版本
RUN PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    rm -rf /opt/php/* && \
    mkdir -p /opt/php/bin /opt/php/sbin && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /opt/php/bin/php && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /usr/bin/php && \
    if [ -f /usr/sbin/php-fpm$(echo ${PHP_VER} | tr -d '.') ]; then \
        ln -sf /usr/sbin/php-fpm$(echo ${PHP_VER} | tr -d '.') /opt/php/sbin/php-fpm; \
    fi

# 3. 動態抓取兩個新版本的真實版號與 OpenSSL 資訊，精準更新面板前端 index.html 顯示文字
RUN NEW_CUSTOM_FULL=$(/opt/php/bin/php -r 'echo PHP_VERSION;') && \
    NEW_CUSTOM_SSL=$(/opt/php/bin/php -r 'echo OPENSSL_VERSION_TEXT;') && \
    NEW_84_FULL=$(/usr/bin/php84 -r 'echo PHP_VERSION;') && \
    NEW_84_SSL=$(/usr/bin/php84 -r 'echo OPENSSL_VERSION_TEXT;') && \
    echo "槽位1新顯示: PHP ${PHP_VER} (${NEW_CUSTOM_FULL}) / ${NEW_CUSTOM_SSL}" && \
    echo "槽位2新顯示: PHP 8.4 (${NEW_84_FULL}) / ${NEW_84_SSL}" && \
    sed -i \
      -e "s|PHP 7\.4 (7\.4\.33) / OpenSSL 1\.0\.2u 20 Dec 2019|PHP ${PHP_VER} (${NEW_CUSTOM_FULL}) / ${NEW_CUSTOM_SSL}|g" \
      -e "s|PHP 8\.4 (8\.4\.21) / OpenSSL 3\.5\.6 7 Apr 2026|PHP 8.4 (${NEW_84_FULL}) / ${NEW_84_SSL}|g" \
      -e "s|PHP 7\.4|PHP ${PHP_VER}|g" \
      /opt/hidden-ui/index.html

# 4. 驗證最終替換後的頁面文字與兩個 PHP 版本狀態
RUN grep -aoE '.{0,10}PHP .{0,55}' /opt/hidden-ui/index.html || true
