FROM livecodesvip/php-runtime:latest

ARG PHP_VER=8.3

USER root

# 1. 先提取原 PHP 7.4 的模組清單並儲存到暫存檔（避免多行變數解析出錯）
RUN /opt/php/bin/php -m \

    | grep -vE '^\[|^(Core|date|filter|hash|json|libxml|openssl|pcre|Reflection|SPL|standard|zlib|mysqlnd|Zend OPcache)$' \
    | tr -d '\r' \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u > /tmp/old_php_modules.txt && \
    cat /tmp/old_php_modules.txt

# 2. 更新軟體源，升級現有的 php84 與底層 OpenSSL 庫，並精準安裝目標 PHP 版本
RUN set -e && \
    PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    apk update && \
    for pkg in $(apk info | grep -E '^php84|^libssl|^libcrypto'); do \
        apk add --no-cache --upgrade "$pkg" || echo "跳過無需升級的套件: $pkg"; \
    done && \
    if [ "${PHP_PKG_PREFIX}" != "php84" ]; then \
        echo "${PHP_PKG_PREFIX}" > /tmp/target_pkgs.txt && \
        echo "${PHP_PKG_PREFIX}-cli" >> /tmp/target_pkgs.txt && \
        echo "${PHP_PKG_PREFIX}-fpm" >> /tmp/target_pkgs.txt && \
        echo "${PHP_PKG_PREFIX}-phar" >> /tmp/target_pkgs.txt && \
        echo "${PHP_PKG_PREFIX}-openssl" >> /tmp/target_pkgs.txt && \
        echo "${PHP_PKG_PREFIX}-json" >> /tmp/target_pkgs.txt && \
        echo "${PHP_PKG_PREFIX}-opcache" >> /tmp/target_pkgs.txt && \
        while IFS= read -r mod; do \
            [ -z "$mod" ] && continue; \
            if apk search -q -x "${PHP_PKG_PREFIX}-${mod}" | grep -q "^${PHP_PKG_PREFIX}-${mod}$"; then \
                echo "${PHP_PKG_PREFIX}-${mod}" >> /tmp/target_pkgs.txt; \
            elif apk search -q -x "${PHP_PKG_PREFIX}-pecl-${mod}" | grep -q "^${PHP_PKG_PREFIX}-pecl-${mod}$"; then \
                echo "${PHP_PKG_PREFIX}-pecl-${mod}" >> /tmp/target_pkgs.txt; \
            fi; \
        done < /tmp/old_php_modules.txt && \
        sort -u /tmp/target_pkgs.txt | xargs apk add --no-cache; \
    fi && \
    rm -rf /var/cache/apk/* /tmp/old_php_modules.txt /tmp/target_pkgs.txt

# 3. 清理舊版 PHP 7.4 二進位殘留，並建立軟連結將 /opt/php 指向新指定的 PHP 版本
RUN PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    rm -rf /opt/php/* && \
    mkdir -p /opt/php/bin /opt/php/sbin && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /opt/php/bin/php && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /usr/bin/php && \
    if [ -f /usr/sbin/php-fpm$(echo ${PHP_VER} | tr -d '.') ]; then \
        ln -sf /usr/sbin/php-fpm$(echo ${PHP_VER} | tr -d '.') /opt/php/sbin/php-fpm; \
    fi

# 4. 動態抓取兩個新版本的真實版號與 OpenSSL 資訊，精準更新面板前端 index.html 顯示文字
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

# 5. 驗證最終替換後的頁面文字
RUN grep -aoE '.{0,10}PHP .{0,55}' /opt/hidden-ui/index.html || true
