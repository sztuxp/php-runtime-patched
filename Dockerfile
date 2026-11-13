FROM livecodesvip/php-runtime:latest

ARG PHP_VER=8.3

USER root

# 1. 提取原 PHP 7.4 的模組清單並儲存到暫存檔
RUN /opt/php/bin/php -m \

    | grep -vE '^\[|^(Core|date|filter|hash|json|libxml|openssl|pcre|Reflection|SPL|standard|zlib|mysqlnd|Zend OPcache)$' \
    | tr -d '\r' \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u > /tmp/old_php_modules.txt

# 2. 升級底層系統庫，安裝目標 PHP 版本（維持原插件），並徹底刪除原 PHP 8.4（若目標非 8.4）
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
        sort -u /tmp/target_pkgs.txt | xargs apk add --no-cache && \
        apk del --no-cache $(apk info | grep '^php84') || true && \
        rm -rf /etc/php84 /usr/lib/php84 /usr/share/php84 /usr/include/php84 /var/log/php84; \
    fi && \
    rm -rf /var/cache/apk/* /tmp/old_php_modules.txt /tmp/target_pkgs.txt

# 3. 徹底清理舊版殘留，並建立軟連結對接目標版本（確保 /etc/php84/conf.d 存在供 entrypoint.sh 寫入）
RUN PHP_PKG_PREFIX="php$(echo ${PHP_VER} | tr -d '.')" && \
    PHP_NUM=$(echo ${PHP_VER} | tr -d '.') && \
    rm -rf /opt/php/* /opt/openssl-1.0.2u /opt/curl && \
    mkdir -p /opt/php/bin /opt/php/sbin /opt/openssl-1.0.2u/bin /opt/curl/bin /etc/php${PHP_NUM}/conf.d && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /opt/php/bin/php && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /usr/bin/php && \
    ln -sf /usr/bin/${PHP_PKG_PREFIX} /usr/bin/php84 && \
    ln -sf /usr/bin/openssl /opt/openssl-1.0.2u/bin/openssl && \
    ln -sf /usr/bin/curl /opt/curl/bin/curl && \
    if [ -f /usr/sbin/php-fpm${PHP_NUM} ]; then \
        ln -sf /usr/sbin/php-fpm${PHP_NUM} /opt/php/sbin/php-fpm && \
        ln -sf /usr/sbin/php-fpm${PHP_NUM} /usr/sbin/php-fpm84; \
    fi && \
    if [ "${PHP_NUM}" != "84" ]; then \
        ln -sf /etc/php${PHP_NUM} /etc/php84; \
    fi

# 4. 更新面板：保留預設 php84 啟動 ID 避免狀態衝突，僅顯示唯一目標版本（無切換）
RUN NEW_FULL=$(/opt/php/bin/php -r 'echo PHP_VERSION;') && \
    NEW_SSL=$(/opt/php/bin/php -r 'echo OPENSSL_VERSION_TEXT;') && \
    sed -i "s|PHP 8\.4|PHP ${PHP_VER}|g" /opt/hidden-ui/index.html && \
    sed -i -E \
      -e "s|\"versions\":\[.*\]|\"versions\":[{\"id\":\"php84\",\"php\":\"${NEW_FULL}\",\"openssl\":\"${NEW_SSL}\",\"available\":true}]|g" \
      /usr/local/bin/php-runtime-daemon

# 5. 驗證配置目錄軟連結與唯一 PHP 版本
RUN ls -ld /etc/php84 /etc/php84/conf.d && php -v && grep -n "versions" /usr/local/bin/php-runtime-daemon
