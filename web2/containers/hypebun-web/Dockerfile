# Custom FrankenPHP image for Hypebun Bio (AltumCode).
#
# The base dunglas/frankenphp image ships only a minimal PHP extension set
# (PDO + mysqlnd, no mysqli/gd/etc). AltumCode requires mysqli (core DB layer),
# gd (captcha/image processing) and the common web extensions below.
FROM dunglas/frankenphp:1.13.0-php8.5@sha256:2a9c6663f73ad1e401909634206bd25e13bed5b94d86eefa3b5ec64c985b4595

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
