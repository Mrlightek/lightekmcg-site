FROM ubuntu:24.04 AS blender
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils && rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --retry 2 https://download.blender.org/release/Blender4.5/blender-4.5.16-linux-x64.tar.xz -o /tmp/blender.tar.xz \
 && echo '23432b064977908beb1ab4b7f32f024e7331105c875c187dce002aff84b10c11  /tmp/blender.tar.xz' | sha256sum --check - \
 && mkdir -p /opt/blender && tar -xJf /tmp/blender.tar.xz --strip-components=1 -C /opt/blender && rm /tmp/blender.tar.xz

FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-numpy libx11-6 libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 libsm6 libice6 libgl1 libegl1 libxext6 libtbb12 libgomp1 libfreetype6 libpulse0 libxrandr2 libxcursor1 libxinerama1 libdbus-1-3 ffmpeg fonts-dejavu-core ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=blender /opt/blender /opt/blender
RUN ln -s /opt/blender/blender /usr/local/bin/blender
ENV HOME=/tmp
WORKDIR /work
USER 65532:65532
CMD ["ffmpeg", "-version"]
