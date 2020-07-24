if [ -z "${RUBYGEMS_API_KEY}" ]; then
    echo "RUBYGEMS_API_KEY environment variable not set."
    exit 1
fi

mkdir ~/.gem
echo -e "---\r\n:rubygems_api_key: ${RUBYGEMS_API_KEY}" > ~/.gem/credentials
chmod 0600 /home/circleci/.gem/credentials
