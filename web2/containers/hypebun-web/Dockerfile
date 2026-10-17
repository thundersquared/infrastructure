# Custom FrankenPHP image for Hypebun Bio (AltumCode).
#
# The base dunglas/frankenphp image ships only a minimal PHP extension set
# (PDO + mysqlnd, no mysqli/gd/etc). AltumCode requires mysqli (core DB layer),
# gd (captcha/image processing) and the common web extensions below.
FROM dunglas/frankenphp:1.13.1-php8.5@sha256:4a8eebee6b3bed92d01ffa6ec5b1bc2cb9c2ab7eeb546027a3f7e6a52937ebbb

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
