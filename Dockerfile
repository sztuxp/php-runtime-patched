FROM livecodesvip/php-runtime:latest

ARG PHP_VER=8.3

USER root

# 1. 提取原 PHP 7.4 的模組清單並儲存到暫存檔
RUN /opt/php/bin/php -m \

    | grep -vE '^\[|^(Core|date|filter|hash|json|libxml|openssl|pcre|Reflection|SPL|standard|zlib|mysqlnd|Zend OPcache)$' \
    | tr -d '\r' \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u > /tmp/old_php_modules.txt

# 2. 更新軟體源，升級現有的 php84 與底層 OpenSSL 庫，並精準安裝目標 PHP 版本
RUN set -e && \
    PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    apk update && \
    apk upgrade --no-cache --available && \
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

# 3. 徹底清理舊版 PHP 7.4、OpenSSL 1.0.2u 與舊版 curl 殘留，建立軟連結對接新版本
RUN PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    PHP_NUM=$(echo ${PHP_VER} | tr -d '.') && \
    rm -rf /opt/php/* /opt/openssl-1.0.2u /opt/curl && \
    mkdir -p /opt/php/bin /opt/php/sbin /opt/openssl-1.0.2u/bin /opt/curl/bin && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /opt/php/bin/php && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /usr/bin/php && \
    ln -sf /usr/bin/openssl /opt/openssl-1.0.2u/bin/openssl && \
    ln -sf /usr/bin/curl /opt/curl/bin/curl && \
    if [ -f /usr/sbin/php-fpm${PHP_NUM} ]; then \
        ln -sf /usr/sbin/php-fpm${PHP_NUM} /opt/php/sbin/php-fpm; \
    fi

# 4. 動態抓取兩個槽位的真實最新資訊，使用通用正則強制替換 php-runtime-daemon 中的 JSON 資料
RUN NEW_CUSTOM_FULL=$(/opt/php/bin/php -r 'echo PHP_VERSION;') && \
    NEW_CUSTOM_SSL=$(/opt/php/bin/php -r 'echo OPENSSL_VERSION_TEXT;') && \
    NEW_84_FULL=$(/usr/bin/php84 -r 'echo PHP_VERSION;') && \
    NEW_84_SSL=$(/usr/bin/php84 -r 'echo OPENSSL_VERSION_TEXT;') && \
    sed -i "s|PHP 7\.4|PHP ${PHP_VER}|g" /opt/hidden-ui/index.html && \
    sed -i -E \
      -e "s|\"id\":\"php74\",\"php\":\"[^\"]+\",\"openssl\":\"[^\"]+\"|\"id\":\"php74\",\"php\":\"${NEW_CUSTOM_FULL}\",\"openssl\":\"${NEW_CUSTOM_SSL}\"|g" \
      -e "s|\"id\":\"php84\",\"php\":\"[^\"]+\",\"openssl\":\"[^\"]+\"|\"id\":\"php84\",\"php\":\"${NEW_84_FULL}\",\"openssl\":\"${NEW_84_SSL}\"|g" \
      /usr/local/bin/php-runtime-daemon

# 5. 在建置日誌中直接驗證第 39 行是否已成功替換為最新真實版號
RUN grep -n "versions" /usr/local/bin/php-runtime-daemon
