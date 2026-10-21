# Custom FrankenPHP image for Hypebun Bio (AltumCode).
#
# The base dunglas/frankenphp image ships only a minimal PHP extension set
# (PDO + mysqlnd, no mysqli/gd/etc). AltumCode requires mysqli (core DB layer),
# gd (captcha/image processing) and the common web extensions below.
FROM dunglas/frankenphp:1.13.2-php8.5@sha256:8a7a935deb33959200628497b8201423c8b777d513a62ac1b69a91c624afdb3d

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
