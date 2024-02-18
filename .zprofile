if [[ $(uname -m) == 'arm64' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  export PATH="/opt/bin:$PATH"
  if [ -d /opt/homebrew/opt/mysql-client/bin ]; then
      export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"
  fi
else
  if [ -d /opt/homebrew/opt/mysql-client/bin ]; then
      export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"
  fi
    
fi
