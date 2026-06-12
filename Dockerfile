# ================= 第一阶段：编译环境 =================
FROM alpine:latest AS builder
RUN apk add --no-cache build-base meson ninja pkgconfig wget xz gnutls-dev gnutls-utils libev-dev readline-dev libtasn1-dev libseccomp-dev protobuf-c-dev protobuf-c-compiler linux-headers linux-pam-dev lz4-dev
WORKDIR /build
ARG OCSERV_VERSION=1.5.0
RUN wget https://www.infradead.org/ocserv/download/ocserv-${OCSERV_VERSION}.tar.xz \
    && tar -xf ocserv-${OCSERV_VERSION}.tar.xz \
    && cd ocserv-${OCSERV_VERSION} \
    && meson setup build -Dprefix=/usr -Dsysconfdir=/etc -Dlocalstatedir=/var -Dradius=disabled -Dgssapi=disabled -Dpam=disabled \
    && ninja -C build \
    && DESTDIR=/install meson install -C build \
    # 完美存放到 /usr/share/ocserv 目录下
    && mkdir -p /install/usr/share/ocserv \
    && cp doc/sample.config /install/usr/share/ocserv/ocserv.conf.template

# ================= 第二阶段：纯净运行环境 =================
FROM alpine:latest
RUN apk add --no-cache gnutls libev readline libtasn1 libseccomp protobuf-c lz4-libs iptables nftables bash gnutls-utils iproute2

# 【已修复】只搬运包含 bin, sbin, share 完整产物的 usr 目录
COPY --from=builder /install/usr /usr

RUN addgroup -S ocserv && adduser -S -G ocserv ocserv

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]