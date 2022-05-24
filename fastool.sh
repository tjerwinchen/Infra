#! /usr/bin/env bash
set -eu

TOOLING_DIR=$(dirname "$0")
SRCROOT=$(pwd)

SWIFTFORMAT_FILE=$TOOLING_DIR/ios/swiftformat
SWIFTLINT_FILE=$TOOLING_DIR/ios/swiftlint.yml
VERBOSE=""
OUTPUT=""
VERSION=nil

function parse_args() {
  while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    --verbose)
      VERBOSE="--verbose"
      # Shift past argument since there's no value expected.
      shift
      ;;
    --version)
      VERSION=$2
      shift # past argument
      shift # past value
      ;;
    # Unknown option.
    *)
      # Save it in an array for later,
      POSITIONAL+=("$1")
      # Shift past argument.
      shift
      ;;
    esac
  done
  # Restore positional parameters.
  set -- "${POSITIONAL[@]}"
}

# swiftformat
function format() {
  if ! which swiftformat &> /dev/null; then
    printf "⚠️  You don't have SwiftFormat installed locally. Learn more about SwiftFormat by visiting https://github.com/nicklockwood/SwiftFormat.\n"
  else
    if [ -f $SWIFTFORMAT_FILE ]; then
      swiftformat --config $SWIFTFORMAT_FILE $SRCROOT $VERBOSE
    else
      printf "Not found $SWIFTLINT_FILE"
      exit 1
    fi
  fi
}

# swiftlint
function lint() {
  if ! which swiftlint &> /dev/null; then
    printf "⚠️  You don't have SwiftLint installed locally. Learn more about SwiftLint by visiting https://github.com/realm/SwiftLint.\n"
    printf "ℹ️️  run \e[0;32minfra/developer-tools/libs/environment/swift.sh\e[0m under monorepo to install tooling\n"
  else
    if [ -f $SWIFTLINT_FILE ]; then
      swiftlint --no-cache --config $SWIFTLINT_FILE $VERBOSE
    else
      printf "Not found $SWIFTLINT_FILE"
      exit 1
    fi
  fi
}

function podlint() {
  if [ -n "${1-}" ]; then
    local podname=$1.podspec
  else
    local podname=$(ls *.podspec)
  fi
    
  if ! which bundle &> /dev/null; then
    printf "⚠️  You don't have Bundler installed locally.\n"
    gem install bundler & bundle install
    bundle exec pod lib lint $podname $VERBOSE
  else
    bundle exec pod lib lint $podname $VERBOSE
  fi
}

function podspeclint() {
  if [ -n "${1-}" ]; then
    local podname=$1.podspec
  else
    local podname=$(ls *.podspec)
  fi
  
  if ! which bundle &> /dev/null; then
    printf "⚠️  You don't have Bundler installed locally.\n"
    gem install bundler & bundle install
  fi
  
  bundle exec pod spec lint $podname $VERBOSE
}

function podpush() {
  if [ -n "${1-}" ]; then
    local podname=$1.podspec
  else
    local podname=$(ls *.podspec)
  fi
  
  if ! which bundle &> /dev/null; then
    printf "⚠️  You don't have Bundler installed locally.\n"
    gem install bundler & bundle install
  fi
  bundle exec pod trunk push $podname $VERBOSE
}

function is_repo_clean() {
  output=$(git status --untracked-files=no --porcelain) && [ -z "$output" ]
}

function is_no_unpushed_commits() {
  output=$(git cherry -v) && [ -z "$output" ]
}

function is_tag_exist_locally() {
  git rev-parse -q --verify "refs/tags/$1" >/dev/null;
}

function is_tag_exist_remotely() {
  git ls-remote --exit-code --tags origin $1 >/dev/null;
}

function remove_tag_locally() {
  git tag -d $1
}

function remove_tag_remotely() {
  git push --delete origin $1
}

function tag() {
  local tag=${VERSION}
  if is_tag_exist_locally $tag; then
    remove_tag_locally $tag
  fi
  if is_tag_exist_remotely $tag; then
    remove_tag_remotely $tag
  fi
  
  git tag -a ${tag} -m "Release version ${tag}"
  git push origin ${tag}
}

function release() {
  local version=${VERSION}
  if is_repo_clean && is_no_unpushed_commits; then
    podspeclint
    tag ${version}
    podpush
  else
    printf "⚠️  You have uncommitted changes or unpushed commits.\n${output}\n"
  fi
}

function generate() {
  xcodegen generate -s Example/Cocoapods/.project.yml --project Example/Cocoapods/
  xcodegen generate -s Example/SPM/.project.yml --project Example/SPM/
}

function mockgen() {
  if ! which .build/checkouts/mockingbird/mockingbird &> /dev/null; then
    swift package update Mockingbird
  fi
  swift package describe --type json > project.json
  .build/checkouts/mockingbird/mockingbird generate --project project.json \
    --disable-swiftlint \
    --output-dir Tests/${PACKAGE_NAME}Tests/Generated \
    --testbundle ${PACKAGE_NAME}Tests \
    --targets $1
}

function check() {
  format
  lint
}

if [[ $1 =~ ^(format|lint|check|podlint|release|generate|mockgen)$ ]]; then
  # Parsing common args
  parse_args "$@"
  "$@"
#  if [ "$OUTPUT" ]; then
#    echo "$OUTPUT" >&2
#    exit 1
#  fi
else
  echo "Invalid subcommand $1" >&2
  echo "Only support format|lint|check|podlint|release|generate|mockgen|tag"
  exit 1
fi
