# Custom FrankenPHP image for Hypebun Bio (AltumCode).
#
# The base dunglas/frankenphp image ships only a minimal PHP extension set
# (PDO + mysqlnd, no mysqli/gd/etc). AltumCode requires mysqli (core DB layer),
# gd (captcha/image processing) and the common web extensions below.
FROM dunglas/frankenphp:1.12.6-php8.5@sha256:b7b15592078ee8f3ed4d7ded9bd6fadc63ce31d8dd927cf191f78d89d21179fd

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
