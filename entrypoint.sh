#!/bin/bash

set -x
# Name the Docker inputs.
#
INPUT_REPOSITORY="$1"
INPUT_BRANCH="$2"
INPUT_HOST="$3"
INPUT_GITHUB_TOKEN="$4"
INPUT_GITHUB_PAT="$5"
INPUT_SOURCE_FOLDER="$6"
INPUT_TARGET_FOLDER="$7"
INPUT_COMMIT_AUTHOR="$8"
INPUT_COMMIT_MESSAGE="$9"
INPUT_DRYRUN="${10}"
INPUT_WORKDIR="${11}"
INPUT_INITIAL_SOURCE_FOLDER="${12}"
INPUT_INITIAL_COMMIT_MESSAGE="${13}"
GITHUB_REF="${14}"
INPUT_TAG_BRANCH="${15}"
INPUT_BASE_BRANCH="${16}"



# Check for required inputs.
#
[ -z "$INPUT_BRANCH" ] && echo >&2 "::error::'branch' is required" && exit 1
[ -z "$INPUT_GITHUB_TOKEN" -a -z "$INPUT_GITHUB_PAT" ] && echo >&2 "::error::'github_token' or 'github_pat' is required -- skipping" && exit 0

# Set state from inputs or defaults.
#
REPOSITORY="${INPUT_REPOSITORY:-${GITHUB_REPOSITORY}}"
BRANCH="${INPUT_BRANCH}"
HOST="${INPUT_GIT_HOST:-github.com}"
TOKEN="${INPUT_GITHUB_PAT:-${INPUT_GITHUB_TOKEN}}"
REMOTE="${INPUT_REMOTE:-https://${TOKEN}@${HOST}/${REPOSITORY}.git}"

SOURCE_FOLDER="${INPUT_SOURCE_FOLDER:-.}"
INITIAL_SOURCE_FOLDER="${INPUT_INITIAL_SOURCE_FOLDER:-${SOURCE_FOLDER}}"
TARGET_FOLDER="${INPUT_TARGET_FOLDER}"

REF="${GITHUB_BASE_REF:-${GITHUB_REF}}"
REF_BRANCH=$(echo "${REF}" | rev | cut -d/ -f1 | rev)
[ -z "$REF_BRANCH" ] && echo 2>&1 "No ref branch" && exit 1

TAG_VALUE=${GITHUB_REF/refs\/tags\//}
if [[ "$GITHUB_REF" == "${GITHUB_REF/refs\/tags\//}"  ]]; then
  IS_TAG=""
else
  git fetch --depth=1 origin +refs/tags/*:refs/tags/*
  GIT_TAG_MESSAGE=$(git tag -l --format='%(contents)' "${TAG_VALUE}")
  BRANCH=$INPUT_TAG_BRANCH
  IS_TAG="TRUE"
fi


if [[ "$GITHUB_REF" != "${GITHUB_REF/refs\/pull\//}"  ]]; then
    echo "Is a pull request, script exited"
    exit 0
fi

COMMIT_AUTHOR="${INPUT_COMMIT_AUTHOR:-${GITHUB_ACTOR} <${GITHUB_ACTOR}@users.noreply.github.com>}"
GIT_MESSAGE=$(git log -1 --pretty=format:%B)
COMMIT_MESSAGE="${INPUT_COMMIT_MESSAGE:-[${GITHUB_WORKFLOW}] Publish


from ${GITHUB_REPOSITORY}:${REF_BRANCH}/${SOURCE_FOLDER}} REV:${GITHUB_SHA}

${GIT_MESSAGE}"
INITIAL_COMMIT_MESSAGE="${INPUT_INITIAL_COMMIT_MESSAGE}

from ${GITHUB_REPOSITORY}:${REF_BRANCH}/${SOURCE_FOLDER} REV:${GITHUB_SHA}

${GIT_MESSAGE}"

# Calculate the real source path.
#
SOURCE_PATH="$(realpath "${SOURCE_FOLDER}")"
INITIAL_SOURCE_PATH="$(realpath "${INITIAL_SOURCE_FOLDER}")"
[ -z "${SOURCE_PATH}" ] && exit 1
[ -z "${INITIAL_SOURCE_PATH}" ] && exit 1
echo "::debug::SOURCE_PATH=${SOURCE_PATH}"
echo "::debug::INITIAL_SOURCE_PATH=${INITIAL_SOURCE_PATH}"

# Let's start doing stuff.
echo "Publishing ${SOURCE_FOLDER} to ${REMOTE}:${BRANCH}/${TARGET_FOLDER}"

# Create a working directory; the workspace may be filled with other important
# files.
#
WORK_DIR="${INPUT_WORKDIR:-$(mktemp -d "${HOME}/gitrepo.XXXXXX")}"
[ -z "${WORK_DIR}" ] && echo >&2 "::error::Failed to create temporary working directory" && exit 1
git config --global --add safe.directory "${WORK_DIR}" || exit 1
cd "${WORK_DIR}"

# Initialize git repo and configure for remote access.
#
echo "Initializing repository with remote ${REMOTE}"
git init || exit 1
ls
git config --global user.email "${COMMIT_AUTHOR}@users.noreply.github.com" || exit 1
echo "git config --global user.email ${COMMIT_AUTHOR}@users.noreply.github.com"
git config --global user.name "${COMMIT_AUTHOR}" || exit 1
echo "git config --global user.name  ${COMMIT_AUTHOR}"
git remote add origin "${REMOTE}" || exit 1
git config --global --list

# Fetch initial (current contents).
#
echo "Fetching ${REMOTE}:${BRANCH}"
if [ "$(git ls-remote --heads "${REMOTE}" "${BRANCH}"  | wc -l)" == 0 ] ; then

    if [ "$(git ls-remote --heads "${REMOTE}" "${INPUT_BASE_BRANCH}"  | wc -l)" == 0 ] ; then
      #Setup base branch if missing
      echo "Initialising ${INPUT_BASE_BRANCH} branch"
      git checkout --orphan "${INPUT_BASE_BRANCH}"
      TARGET_PATH="${WORK_DIR}/${TARGET_FOLDER}"
      echo "Populating ${TARGET_PATH}"
      mkdir -p "${TARGET_PATH}" || exit 1
      rsync -a --quiet --delete --exclude ".git" "${INITIAL_SOURCE_PATH}/" "${TARGET_PATH}" || exit 1

      echo "Creating initial commit"
      git add "${TARGET_PATH}" || exit 1
      git commit -m "${INITIAL_COMMIT_MESSAGE}" --author "${COMMIT_AUTHOR} <${COMMIT_AUTHOR}@users.noreply.github.com>" || exit 1
      COMMIT_HASH="$(git rev-parse HEAD)"
      echo "Created commit ${COMMIT_HASH}"

      if [ -z "${INPUT_DRYRUN}" ] ; then
          echo "Pushing to ${REMOTE}:${BRANCH}"
          git push origin "${BRANCH}" || exit 1
      else
          echo "[DRY-RUN] Not pushing to ${REMOTE}:${BRANCH}"
      fi
    fi

    #Clone from base branch for repo
    git fetch --depth 1 origin "${INPUT_BASE_BRANCH}" || exit 1
    git checkout "${INPUT_BASE_BRANCH}" || exit 1
    git pull origin "${INPUT_BASE_BRANCH}" || exit 1
    git checkout -b "${BRANCH}" || exit 1
    
    if [ -z "${INPUT_DRYRUN}" ] ; then
              echo "Pushing to ${REMOTE}:${BRANCH}"
              git push origin "${BRANCH}" || exit 1
          else
              echo "[DRY-RUN] Not pushing to ${REMOTE}:${BRANCH}"
    fi

else
    git fetch --depth 1 origin "${BRANCH}" || exit 1
    git checkout -b "${BRANCH}" || exit 1
    git pull origin "${BRANCH}" || exit 1
fi

# Create the target directory (if necessary) and copy files from source.
#
TARGET_PATH="${WORK_DIR}/${TARGET_FOLDER}"
echo "Populating ${TARGET_PATH}"
mkdir -p "${TARGET_PATH}" || exit 1
rsync -a --quiet --delete --exclude ".git" "${SOURCE_PATH}/" "${TARGET_PATH}" || exit 1

# Check changes
#
if [ -z "$(git status -s)" ] ; then
   if [ "${IS_TAG}" = "TRUE" ] ; then
     git tag "${TAG_VALUE}" -m "$GIT_TAG_MESSAGE"
     if [ -z "${INPUT_DRYRUN}" ] ; then
       echo "Pushing to tag ${REMOTE}:${TAG_VALUE}"
       git push origin "${TAG_VALUE}"
       else
           echo "[DRY-RUN] Not pushing tag to ${REMOTE}:${TAG_VALUE}"
       fi
    fi
    echo "No changes, script exited"
    exit 0
fi

# Create commit with changes.
#
echo "Creating commit"
git add "${TARGET_PATH}" || exit 1
git commit -m "${COMMIT_MESSAGE}" --author "${COMMIT_AUTHOR} <${COMMIT_AUTHOR}@users.noreply.github.com>" || exit 1
COMMIT_HASH="$(git rev-parse HEAD)"
echo "Created commit ${COMMIT_HASH}"

# Publish output variables.
#
echo "::set-output name=commit_hash::${COMMIT_HASH}"
echo "::set-output name=working_directory::${WORK_DIR}"

# Push if not a dry-run.
#
if [ -z "${INPUT_DRYRUN}" ] ; then
    echo "Pushing to ${REMOTE}:${BRANCH}"
    git push origin "${BRANCH}" || exit 1
else
    echo "[DRY-RUN] Not pushing to ${REMOTE}:${BRANCH}"
fi

if [ "${IS_TAG}" = "TRUE" ]; then
  git tag "${TAG_VALUE}" -m "$GIT_TAG_MESSAGE"
 if [ -z "${INPUT_DRYRUN}" ] ; then
   echo "Pushing to tag ${REMOTE}:${TAG_VALUE}"
   git push origin "${TAG_VALUE}"
   else
       echo "[DRY-RUN] Not pushing tag to ${REMOTE}:${TAG_VALUE}"
   fi
fi
