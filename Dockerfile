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
    # 【核心修改】放到 /usr/share 下，绝对不会被宿主机的 volume 挂载盖住
    && mkdir -p /install/usr/share/ocserv \
    && cp doc/sample.config /install/usr/share/ocserv/ocserv.conf.template

# ================= 第二阶段：纯净运行环境 =================
FROM alpine:latest
RUN apk add --no-cache gnutls libev readline libtasn1 libseccomp protobuf-c lz4-libs iptables nftables bash gnutls-utils iproute2
COPY --from=builder /install/usr /usr
COPY --from=builder /install/etc /etc

RUN addgroup -S ocserv && adduser -S -G ocserv ocserv

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]