FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends blender ffmpeg ca-certificates && rm -rf /var/lib/apt/lists/*
ENV HOME=/tmp
WORKDIR /work
USER 65532:65532
CMD ["ffmpeg", "-version"]
