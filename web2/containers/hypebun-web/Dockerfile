# Custom FrankenPHP image for Hypebun Bio (AltumCode).
#
# The base dunglas/frankenphp image ships only a minimal PHP extension set
# (PDO + mysqlnd, no mysqli/gd/etc). AltumCode requires mysqli (core DB layer),
# gd (captcha/image processing) and the common web extensions below.
FROM dunglas/frankenphp:1.14.0-php8.5@sha256:b8e0919047838ea32771ef573d74df9a9128de1e908a999366e26c11bc6e7ba4

# docker-php-extension-installer is bundled in the base image.
RUN install-php-extensions \
	mysqli \
	pdo_mysql \
	gd \
	intl \
	zip \
	exif \
	bcmath \
	gmp \
	opcache
