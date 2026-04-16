FROM debian:12-slim

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install nginx
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Copy static files to nginx html directory
COPY ./notebook.html /var/www/html/index.html

# Start nginx in the foreground
CMD ["nginx", "-g", "daemon off;"]