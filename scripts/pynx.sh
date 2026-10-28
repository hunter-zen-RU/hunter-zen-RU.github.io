#!/usr/bin/env bash
# =============================================================================
# pyp.sh - Python bootstrap + virtualenv + package installer with a built-in,
#          numbered package LIBRARY addressed by an "index key pointer" (ikp).
#
# RUN IT STRAIGHT FROM THE GIST
#   URL=https://gist.githubusercontent.com/hunter-zen-RU/5d2a7836d4326167e167bf5eb7f612d4/raw/pyp.sh
#
#   curl -fsSL $URL | bash -s -- -y flask requests       # works in EVERY shell (fish too)
#   bash <(curl -fsSL $URL) -y flask requests            # bash/zsh only (fish has no <( ))
#   bash <(curl -fsSL $URL) -y -L 0x15                   # packages chosen by ikp
#   curl -fsSL $URL | bash -s -- -y -L 1                 # library entry [1]
#   source <(curl -fsSL $URL) -y -L 0x15                 # also ACTIVATES the venv
#
# LIBRARY + IKP  (full spec for people and AIs: ikp-prompt.md in the same gist)
#   Every package in the library below has a permanent index: 1, 2, 3 ...
#   -L N         one index                     -L 1     -> [1]
#   -L 0xHEX     an ikp = several indices      -L 0x15  -> [1] [3] [5]
#   FORMULA (computed by the user or an AI - this script only DECODES it):
#       ikp = "0x" + hex( sum of 2^(i-1) for every selected index i )
#       [1]+[3]+[5]  ->  2^0 + 2^2 + 2^4 = 1 + 4 + 16 = 21 = 0x15
#   Blocks of four (for big libraries): indices 1-4 form block 0 = the right-most
#   hex digit, 5-8 block 1, 9-12 block 2 ...; inside a block the weights are
#   1, 2, 4, 8.  Digit = sum of the weights of the selected indices in the block.
#
#   !! THE LIBRARY IS APPEND-ONLY !!  Never reorder, delete or insert rows: ikps
#   stored in other people's projects point at these positions.  To retire a
#   package keep the row and start its description with "DEPRECATED".  When you
#   append rows, bump PYI_LIB_VERSION.
#
# Run with --help for all options, --list-lib to see the library.
# =============================================================================

PYI_VERSION="3.0.0"
PYI_LIB_VERSION=1
PYI_RAW_URL="https://gist.githubusercontent.com/hunter-zen-RU/5d2a7836d4326167e167bf5eb7f612d4/raw/pyp.sh"

# ----------------------------------------------------------------------------
# THE LIBRARY  -  "pip-name|Category|Description"   (index = position, from 1)
# ----------------------------------------------------------------------------
__pyi_LIB=(
    "requests|Networking|HTTP library for humans"
    "httpx|Networking|Modern sync/async HTTP client"
    "aiohttp|Networking|Async HTTP client and server"
    "urllib3|Networking|Low-level HTTP client"
    "websockets|Networking|WebSocket client and server"
    "paramiko|Networking|SSH2 protocol library"
    "certifi|Networking|Mozilla CA certificate bundle"
    "dnspython|Networking|DNS toolkit"
    "flask|Web|Lightweight WSGI web framework"
    "django|Web|Batteries-included web framework"
    "fastapi|Web|Fast async API framework"
    "uvicorn|Web|ASGI server"
    "gunicorn|Web|WSGI HTTP server"
    "starlette|Web|ASGI toolkit"
    "jinja2|Web|Template engine"
    "werkzeug|Web|WSGI utility library"
    "djangorestframework|Web|REST toolkit for Django"
    "flask-cors|Web|CORS support for Flask"
    "python-multipart|Web|Multipart form parser"
    "pydantic|Web|Data validation using type hints"
    "celery|Web|Distributed task queue"
    "streamlit|Web|Data apps in pure Python"
    "gradio|Web|Quick web UIs for ML demos"
    "sqlalchemy|Database|SQL toolkit and ORM"
    "alembic|Database|SQLAlchemy migrations"
    "psycopg2-binary|Database|PostgreSQL adapter"
    "pymysql|Database|Pure-Python MySQL client"
    "pymongo|Database|MongoDB driver"
    "redis|Database|Redis client"
    "sqlmodel|Database|SQLAlchemy + Pydantic models"
    "peewee|Database|Small ORM"
    "duckdb|Database|In-process analytical database"
    "elasticsearch|Database|Elasticsearch client"
    "numpy|Data|N-dimensional arrays"
    "pandas|Data|DataFrames and data analysis"
    "scipy|Data|Scientific computing"
    "matplotlib|Data|Plotting library"
    "seaborn|Data|Statistical data visualization"
    "plotly|Data|Interactive graphing"
    "polars|Data|Fast DataFrame library"
    "pyarrow|Data|Apache Arrow bindings"
    "openpyxl|Data|Read/write Excel xlsx files"
    "xlsxwriter|Data|Write Excel xlsx files"
    "tabulate|Data|Pretty-print tables"
    "statsmodels|Data|Statistical modeling"
    "sympy|Data|Symbolic mathematics"
    "networkx|Data|Graph and network analysis"
    "dask|Data|Parallel computing"
    "altair|Data|Declarative visualization"
    "scikit-learn|ML/AI|Machine learning toolkit"
    "scikit-image|ML/AI|Image processing"
    "torch|ML/AI|PyTorch deep learning"
    "torchvision|ML/AI|PyTorch vision utilities"
    "torchaudio|ML/AI|PyTorch audio utilities"
    "tensorflow|ML/AI|TensorFlow deep learning"
    "keras|ML/AI|Keras deep learning API"
    "transformers|ML/AI|Hugging Face Transformers"
    "datasets|ML/AI|Hugging Face Datasets"
    "tokenizers|ML/AI|Fast tokenizers"
    "sentencepiece|ML/AI|Subword tokenizer"
    "accelerate|ML/AI|Hugging Face training accelerator"
    "xgboost|ML/AI|Gradient boosting"
    "lightgbm|ML/AI|Gradient boosting"
    "catboost|ML/AI|Gradient boosting"
    "onnxruntime|ML/AI|ONNX model runtime"
    "opencv-python|ML/AI|OpenCV computer vision"
    "pillow|ML/AI|Image library (PIL)"
    "openai|ML/AI|OpenAI API client"
    "anthropic|ML/AI|Anthropic API client"
    "langchain|ML/AI|LLM application framework"
    "tiktoken|ML/AI|Fast BPE tokenizer"
    "huggingface-hub|ML/AI|Hugging Face Hub client"
    "nltk|ML/AI|Natural language toolkit"
    "spacy|ML/AI|Industrial NLP"
    "gensim|ML/AI|Topic modelling"
    "jupyterlab|Notebook|JupyterLab interface"
    "notebook|Notebook|Classic Jupyter Notebook"
    "ipython|Notebook|Interactive Python shell"
    "ipykernel|Notebook|Jupyter kernel for Python"
    "rich|CLI|Rich text and formatting in terminals"
    "click|CLI|Command line toolkit"
    "typer|CLI|CLI apps from type hints"
    "colorama|CLI|Cross-platform colored terminal text"
    "tqdm|CLI|Progress bars"
    "questionary|CLI|Interactive prompts"
    "prompt-toolkit|CLI|Interactive command lines"
    "termcolor|CLI|ANSI color formatting"
    "python-dotenv|CLI|Load .env files"
    "pyyaml|CLI|YAML parser/emitter"
    "tomli|CLI|TOML parser"
    "pytest|Testing|Testing framework"
    "pytest-cov|Testing|Coverage plugin for pytest"
    "pytest-asyncio|Testing|Asyncio support for pytest"
    "tox|Testing|Test automation"
    "coverage|Testing|Code coverage measurement"
    "hypothesis|Testing|Property-based testing"
    "faker|Testing|Fake data generator"
    "responses|Testing|Mock the requests library"
    "black|Quality|Code formatter"
    "ruff|Quality|Fast linter and formatter"
    "flake8|Quality|Style guide enforcement"
    "pylint|Quality|Static code analysis"
    "mypy|Quality|Static type checker"
    "isort|Quality|Import sorter"
    "pre-commit|Quality|Git hook manager"
    "build|Packaging|PEP 517 package builder"
    "twine|Packaging|Upload packages to PyPI"
    "setuptools|Packaging|Build system"
    "wheel|Packaging|Wheel packaging"
    "virtualenv|Packaging|Virtual environments"
    "pipx|Packaging|Install CLI apps in isolation"
    "pip-tools|Packaging|Pin and sync requirements"
    "poetry|Packaging|Dependency management"
    "pyinstaller|Packaging|Bundle apps as executables"
    "beautifulsoup4|Parsing|HTML/XML parsing"
    "lxml|Parsing|Fast XML/HTML processing"
    "html5lib|Parsing|HTML5 parser"
    "selenium|Scraping|Browser automation"
    "playwright|Scraping|Modern browser automation"
    "scrapy|Scraping|Web crawling framework"
    "yt-dlp|Scraping|Video downloader"
    "python-dateutil|Utils|Date/time extensions"
    "pytz|Utils|Time zone definitions"
    "arrow|Utils|Friendlier dates and times"
    "pendulum|Utils|Easy datetimes"
    "regex|Utils|Advanced regular expressions"
    "orjson|Utils|Fast JSON"
    "ujson|Utils|Ultra-fast JSON"
    "msgpack|Utils|MessagePack serialization"
    "protobuf|Utils|Protocol Buffers"
    "jsonschema|Utils|JSON Schema validation"
    "marshmallow|Utils|Object serialization"
    "attrs|Utils|Classes without boilerplate"
    "cachetools|Utils|Caching utilities"
    "tenacity|Utils|Retrying library"
    "loguru|Utils|Simple logging"
    "structlog|Utils|Structured logging"
    "email-validator|Utils|Email address validation"
    "validators|Utils|Value validators"
    "psutil|Utils|System and process utilities"
    "watchdog|Utils|Filesystem event monitoring"
    "schedule|Utils|Job scheduling for humans"
    "apscheduler|Utils|Advanced Python scheduler"
    "pyperclip|Utils|Clipboard access"
    "markdown|Documents|Markdown to HTML"
    "pypdf|Documents|Read/write PDF files"
    "reportlab|Documents|Generate PDF files"
    "python-docx|Documents|Read/write Word files"
    "python-pptx|Documents|Read/write PowerPoint files"
    "qrcode|Documents|QR code generator"
    "mkdocs|Documents|Project documentation"
    "sphinx|Documents|Documentation generator"
    "boto3|Cloud|AWS SDK"
    "botocore|Cloud|AWS low-level client"
    "google-cloud-storage|Cloud|Google Cloud Storage client"
    "azure-storage-blob|Cloud|Azure Blob Storage client"
    "kubernetes|Cloud|Kubernetes API client"
    "docker|Cloud|Docker Engine API client"
    "fabric|Cloud|Remote execution over SSH"
    "cryptography|Security|Cryptographic recipes"
    "bcrypt|Security|Password hashing"
    "pyjwt|Security|JSON Web Tokens"
    "passlib|Security|Password hashing framework"
    "pycryptodome|Security|Low-level crypto primitives"
    "pyopenssl|Security|OpenSSL wrapper"
    "pygame|Apps|Games and multimedia"
    "pyqt6|Apps|Qt6 GUI bindings"
    "discord.py|Apps|Discord bot API"
    "python-telegram-bot|Apps|Telegram bot API"
    "tweepy|Apps|X/Twitter API client"
)

# ----------------------------------------------------------------------------
# Helpers (they read the option variables of __pyi_run through bash's dynamic
# scoping; they are all unset again at the end when the script is sourced)
# ----------------------------------------------------------------------------
__pyi_usage() {
    cat <<EOF
pyp $PYI_VERSION - Python bootstrap + virtualenv + package installer

USAGE
  pyp.sh [options] [package ...]
  source pyp.sh [options] [package ...]    (also activates the venv)

  With no packages and no -L, requirements.txt in the current directory is used.
  If Python 3.8+ (with venv/pip) is missing it is installed first, using the
  system package manager (apt, dnf, yum, zypper, pacman, apk, brew, pkg,
  winget).

RUN FROM A GITHUB GIST
  curl -fsSL $PYI_RAW_URL | bash -s -- -y flask requests     # any shell, incl. fish
  bash <(curl -fsSL $PYI_RAW_URL) -y flask requests          # bash/zsh only
  source <(curl -fsSL $PYI_RAW_URL) -y -r requirements.txt    # + activates venv

OPTIONS
  -r, --requirements FILE   Requirements file or http(s) URL (default: requirements.txt)
  -e, --env DIR             Virtualenv directory           (default: myenv)
  -p, --python EXE          Python interpreter to use      (default: auto-detect)
      --no-install-python   Never install Python; fail if it is missing
  -L, --lib IKP             Install library entries by index / ikp (repeatable, comma lists ok)
      --list-lib            Print the library with indices and exit
      --filter TEXT         With --list-lib: only rows containing TEXT
      --md                  With --list-lib: Markdown table (for docs / AI prompts)
  -y, --yes                 Do not ask for confirmation
  -u, --upgrade             Pass --upgrade to pip for every package
      --upgrade-pip         Upgrade pip inside the venv first
  -R, --recreate            Delete and recreate the venv
  -f, --fail-fast           Stop at the first failure (default: keep going)
  -n, --dry-run             Show what would be installed, change nothing
  -l, --log FILE            Save the full pip output to FILE
      --freeze FILE         Write 'pip freeze' of the venv to FILE when done
      --report FILE         Write the summary report (plain text) to FILE
      --no-activate         Do not activate the venv (when sourced)
  -q, --quiet               Only print errors and a one-line summary
  -v, --verbose             Show pip's output for every package
      --no-color            Disable colors (NO_COLOR env var is honoured too)
  -V, --version             Show version
  -h, --help                Show this help

LIBRARY AND IKP  (Index Key Pointer)
  pyp ships a numbered library of popular pip packages: see --list-lib.
  -L picks entries from it:
    -L 1             plain number = ONE index        -> entry [1]
    -L 0x15          0x-prefixed hex = an ikp        -> entries [1] [3] [5]
    -L 1,0x14 -L 7   several -L / comma lists are merged
  A plain number is always a single index; hex always needs the 0x prefix.
  The ikp is calculated by YOU or an AI (this script only decodes it):
    ikp = 0x + hex( sum of 2^(i-1) for each selected index i )
    [1]+[3]+[5] = 2^0 + 2^2 + 2^4 = 1 + 4 + 16 = 21 = 0x15
  Big libraries: indices come in blocks of 4 (1-4, 5-8, ...). Block 0 is the
  right-most hex digit; inside a block the weights are 1,2,4,8 and the digit
  is the sum of the weights of the selected indices.
  The library is append-only, so an ikp keeps its meaning forever. Check a
  selection before installing with:  pyp.sh -n -L <ikp>
  Spec for AIs (use as a prompt): ikp-prompt.md in
    https://gist.github.com/hunter-zen-RU/5d2a7836d4326167e167bf5eb7f612d4

REQUIREMENTS FILE SUPPORT
  comments (# ...), blank lines, CRLF line endings, line continuation (\\),
  nested '-r other.txt', and global options such as --index-url /
  --extra-index-url / --find-links / --pre.

EXIT CODES
  0 all OK   1 one or more packages failed / runtime error
  2 bad usage   130 interrupted

EXAMPLES
  pyp.sh                       # use ./requirements.txt (asks first)
  pyp.sh -y flask requests     # install two packages
  pyp.sh -r dev.txt -e .venv --freeze lock.txt --report report.txt
  pyp.sh --list-lib --filter http    # find library indices
  pyp.sh -y -L 1                     # requests only (library entry 1)
  pyp.sh -n -L 0x15                  # preview what ikp 0x15 selects
  pyp.sh -y -L 0x15 rich -e .venv    # library selection + extra package
  source pyp.sh -y -u numpy    # install/upgrade and stay activated
EOF
}

__pyi_err()  { printf '%s%s error:%s %s\n' "$R" "$S_FAIL" "$Z" "$*" >&2; }
__pyi_warn() { printf '%s%s%s %s\n' "$Y" "$S_WARN" "$Z" "$*" >&2; }
__pyi_say()  { (( quiet )) || printf '%s\n' "$*"; }

__pyi_need() {   # usage: __pyi_need "$@"  (checks an option has a value)
    if (( $# < 2 )); then
        printf 'error: option %s requires a value (see --help)\n' "$1" >&2
        return 1
    fi
}

__pyi_now() {    # sets NOW (milliseconds)
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        local t=${EPOCHREALTIME/[.,]/}
        NOW=$(( t / 1000 ))
    else
        NOW=$(( SECONDS * 1000 ))
    fi
}

__pyi_fmt_ms() { # sets FMT, e.g. "3.4s" or "1m 05s"
    local ms=$1
    if (( ms >= 60000 )); then
        printf -v FMT '%dm %02ds' $(( ms / 60000 )) $(( ms % 60000 / 1000 ))
    else
        FMT="$(( ms / 1000 )).$(( ms % 1000 / 100 ))s"
    fi
}

__pyi_bar() {    # args: done total width -> sets BAR_F (filled) BAR_E (empty)
    local d=$1 t=$2 w=$3 f i
    (( t > 0 )) || t=1
    f=$(( d * w / t ))
    BAR_F=""; BAR_E=""
    for (( i = 0; i < w; i++ )); do
        if (( i < f )); then BAR_F+="$FILL"; else BAR_E+="$EMPTY"; fi
    done
}

__pyi_name() {   # display name of a requirement spec (strip version/extras)
    local s=$1
    if [[ $s == -* || $s == *://* || $s == ./* || $s == /* ]]; then
        printf '%s' "$s"
    else
        printf '%s' "${s%%[<>=!~;@ \[]*}"
    fi
}

# draw one frame of the live progress line
__pyi_draw() {
    local frame=${SPIN[$1 % ${#SPIN[@]}]} secs=$2 lbl=$spin_label maxl
    if (( bar_total > 0 )); then
        __pyi_bar "$bar_done" "$bar_total" 20
        maxl=$(( cols - 52 )); (( maxl < 12 )) && maxl=12
        (( ${#lbl} > maxl )) && lbl="${lbl:0:maxl-3}..."
        printf '\r\033[K  [%s%s%s%s%s] %s/%s  %s%s%s %s %s(%ss)%s' \
            "$G" "$BAR_F" "$D" "$BAR_E" "$Z" "$bar_done" "$bar_total" \
            "$C" "$frame" "$Z" "$lbl" "$D" "$secs" "$Z"
    else
        printf '\r\033[K  %s%s%s %s %s(%ss)%s' "$C" "$frame" "$Z" "$lbl" "$D" "$secs" "$Z"
    fi
}

# ask a yes/no question; works even when stdin is the script (curl | bash)
# returns 0 = yes, 1 = no, 2 = no terminal available
__pyi_confirm() {
    local reply
    if { : </dev/tty; } 2>/dev/null; then
        printf '%s' "$1" >/dev/tty
        IFS= read -r reply </dev/tty
    elif [[ -t 0 ]]; then
        printf '%s' "$1"
        IFS= read -r reply
    else
        return 2
    fi
    [[ $reply =~ ^([yY][eE][sS]|[yY])$ ]]
}

__pyi_fetch() {  # args: url dest
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 --connect-timeout 15 -o "$2" "$1" </dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1" </dev/null
    else
        return 1
    fi
}

# look for a usable Python (3.8+, with venv + pip). Sets py_found / py_problem
__pyi_find_python() {
    py_found=""; py_problem="missing"
    local c; local -a cands
    if [[ -n $py_requested ]]; then cands=("$py_requested")
    else cands=(python3 python python3.13 python3.12 python3.11 python3.10 python3.9 python3.8); fi
    for c in "${cands[@]}"; do
        command -v "$c" >/dev/null 2>&1 || continue
        if ! "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' </dev/null >/dev/null 2>&1; then
            [[ $py_problem == missing ]] && py_problem="old"
            continue
        fi
        if ! "$c" -c 'import venv' </dev/null >/dev/null 2>&1 \
           || ! "$c" -m ensurepip --version </dev/null >/dev/null 2>&1; then
            py_problem="novenv"
            continue
        fi
        py_found=$c; py_problem=""
        return 0
    done
    return 1
}

# install Python with whatever package manager this system has
__pyi_install_python() {
    local os pm="" sudo="" step i n log
    local -a steps=()
    os=$(uname -s 2>/dev/null || echo unknown)
    local apt_env="env DEBIAN_FRONTEND=noninteractive"
    (( EUID != 0 )) && command -v sudo >/dev/null 2>&1 && sudo="sudo "

    case $os in
        Darwin)
            if command -v brew >/dev/null 2>&1; then pm=brew; sudo=""; steps=("brew install python"); fi ;;
        MINGW*|MSYS*|CYGWIN*)
            sudo=""
            if command -v pacman >/dev/null 2>&1; then
                pm=pacman; steps=("pacman -S --noconfirm --needed python python-pip")
            elif command -v winget >/dev/null 2>&1; then
                pm=winget
                steps=("winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements --silent")
            fi ;;
        *)
            if [[ -n ${TERMUX_VERSION:-} || -d /data/data/com.termux/files/usr ]]; then
                pm=pkg; sudo=""; steps=("pkg install -y python")
            elif command -v apt-get >/dev/null 2>&1; then
                pm=apt; steps=("${sudo}${apt_env} apt-get update -qq" "${sudo}${apt_env} apt-get install -y python3 python3-venv python3-pip")
            elif command -v dnf >/dev/null 2>&1; then
                pm=dnf; steps=("${sudo}dnf install -y python3 python3-pip")
            elif command -v yum >/dev/null 2>&1; then
                pm=yum; steps=("${sudo}yum install -y python3 python3-pip")
            elif command -v zypper >/dev/null 2>&1; then
                pm=zypper; steps=("${sudo}zypper --non-interactive install python3 python3-pip")
            elif command -v pacman >/dev/null 2>&1; then
                pm=pacman; steps=("${sudo}pacman -S --noconfirm --needed python python-pip")
            elif command -v apk >/dev/null 2>&1; then
                pm=apk; steps=("${sudo}apk add --no-cache python3 py3-pip")
            fi ;;
    esac

    if [[ -z $pm ]]; then
        __pyi_err "No supported package manager found on this system ($os)."
        case $os in
            Darwin) echo "  Install Homebrew (https://brew.sh) or Python from https://www.python.org/downloads/ and run again." >&2 ;;
            MINGW*|MSYS*|CYGWIN*) echo "  Install Python from https://www.python.org/downloads/windows/ (or 'winget') and run again." >&2 ;;
            *) echo "  Install Python 3.8+ (with venv and pip) manually, then run again." >&2 ;;
        esac
        return 1
    fi

    # root rights needed? ask for the password *before* the spinner starts
    if [[ $pm =~ ^(apt|dnf|yum|zypper|pacman|apk)$ ]] && (( EUID != 0 )); then
        if [[ -z $sudo ]]; then
            __pyi_err "Installing Python needs root rights and 'sudo' is not available. Re-run as root."
            return 1
        fi
        if ! sudo -n true 2>/dev/null </dev/null; then
            __pyi_say "  ${Y}${S_WARN}${Z} Administrator rights are needed to install Python:"
            if ! sudo -v </dev/null; then
                __pyi_err "Could not obtain administrator rights."
                return 1
            fi
        fi
    fi

    n=${#steps[@]}
    for (( i = 0; i < n; i++ )); do
        step=${steps[i]}
        log="$work/pyp_python_$i.log"
        spin_label="Installing Python via $pm ($(( i + 1 ))/$n)"; bar_total=0
        __pyi_spin "$log" bash -c "$step"
        if (( spin_rc == 130 )); then __pyi_say "${Y}Interrupted.${Z}"; interrupted=1; return 130; fi
        if (( spin_rc != 0 )); then
            __pyi_err "Python installation failed ($pm, exit $spin_rc). Last output:"
            tail -n 15 "$log" | sed 's/^/    /' >&2
            return 1
        fi
    done

    if [[ $pm == winget ]] && command -v cygpath >/dev/null 2>&1 && [[ -n ${LOCALAPPDATA:-} ]]; then
        local wp; wp="$(cygpath -u "$LOCALAPPDATA")/Programs/Python/Python312"
        [[ -d $wp ]] && export PATH="$wp:$wp/Scripts:$PATH"   # winget does not update this shell's PATH
    fi
    hash -r 2>/dev/null
    return 0
}

# run a command in the background with a spinner; result code -> spin_rc
__pyi_spin() {   # args: logfile cmd...
    local log=$1; shift
    local i=0 t0 secs
    "$@" >"$log" 2>&1 </dev/null &      # never let children read stdin (it may be this script)
    child=$!
    __pyi_now; t0=$NOW
    if (( animate )); then
        printf '\033[?25l'
        while kill -0 "$child" 2>/dev/null; do
            __pyi_now; secs=$(( (NOW - t0) / 1000 ))
            __pyi_draw "$i" "$secs"
            i=$(( i + 1 ))
            sleep 0.1
        done
    fi
    wait "$child" 2>/dev/null
    spin_rc=$?
    if (( interrupted )); then          # trap woke 'wait' early: reap child
        kill "$child" 2>/dev/null
        wait "$child" 2>/dev/null
        spin_rc=130
    fi
    child=""
    (( animate )) && printf '\r\033[K\033[?25h'
    return 0
}

# parse a requirements file into 'packages' / 'global_opts'
__pyi_parse_req() {   # args: file [depth]
    local file=$1 depth=${2:-0} line pending="" sub origin="" dl
    local -a parts
    if (( depth > 5 )); then
        __pyi_warn "Skipping '$file': -r nesting is too deep (loop?)"; return
    fi
    if [[ $file =~ ^https?:// ]]; then                  # remote requirements file (e.g. a gist)
        origin=$file
        dl="$work/req_${depth}_$RANDOM.txt"
        if ! __pyi_fetch "$origin" "$dl"; then
            __pyi_err "Could not download requirements file: $origin"
            parse_errors=$(( parse_errors + 1 )); return
        fi
        file=$dl
    fi
    if [[ ! -f $file ]]; then
        __pyi_err "Requirements file not found: $file"
        parse_errors=$(( parse_errors + 1 )); return
    fi
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        if [[ $line == *\\ ]]; then pending+="${line%\\} "; continue; fi
        line="$pending$line"; pending=""
        [[ $line =~ ^[[:space:]]*# ]] && continue
        line=${line%%[[:space:]]#*}                         # inline comment
        line="${line#"${line%%[![:space:]]*}"}"             # ltrim
        line="${line%"${line##*[![:space:]]}"}"             # rtrim
        [[ -z $line ]] && continue

        if [[ $line =~ ^(-r|--requirement)[[:space:]=]*(.+)$ ]]; then
            sub=${BASH_REMATCH[2]}
            if [[ $sub =~ ^https?:// ]]; then :
            elif [[ -n $origin ]]; then sub="${origin%/*}/$sub"
            elif [[ $sub != /* ]]; then sub="$(dirname "$file")/$sub"; fi
            __pyi_parse_req "$sub" $(( depth + 1 ))
        elif [[ $line =~ ^(-i|--index-url|--extra-index-url|-f|--find-links|--trusted-host|--pre|--no-index|--no-binary|--only-binary|--prefer-binary)([[:space:]=]|$) ]]; then
            read -ra parts <<<"$line"
            global_opts+=("${parts[@]}")
        else
            packages+=("$line")
        fi
    done < "$file"
}

# ---- library helpers --------------------------------------------------------
__pyi_add_tokens() {   # "1,0x14" -> lib_tokens+=(1 0x14)
    local -a t
    if [[ -z ${1//[ ,]/} ]]; then __pyi_err "-L needs an index or an ikp, e.g. -L 1 or -L 0x15 (see --help)."; return 1; fi
    IFS=, read -ra t <<<"$1"
    lib_tokens+=("${t[@]}")
}

# decode ONE token into lib_flag[index]=1.  plain number = single index,
# 0x<hex> = ikp bitmask read digit by digit (no size limit, no 64-bit overflow)
__pyi_decode_token() {
    local tok=${1// /} hex d v pos b idx len n=${#__pyi_LIB[@]} found=0
    if [[ $tok =~ ^[0-9]+$ ]]; then
        if (( ${#tok} > 6 )); then __pyi_err "-L '$tok': number too large."; return 1; fi
        idx=$(( 10#$tok ))
        if (( idx < 1 )); then __pyi_err "-L '$tok': library indices start at 1."; return 1; fi
        if (( idx > n )); then
            __pyi_err "-L $tok: index $idx is not in this library (v$PYI_LIB_VERSION has $n entries). Is your copy of pyp.sh older than the one this ikp was made for?"
            return 1
        fi
        lib_flag[idx]=1
    elif [[ $tok =~ ^0[xX]([0-9a-fA-F]+)$ ]]; then
        hex=${BASH_REMATCH[1]}; len=${#hex}
        for (( pos = 0; pos < len; pos++ )); do
            d=${hex:len-1-pos:1}
            v=$(( 16#$d ))
            for b in 0 1 2 3; do
                if (( v & (1 << b) )); then
                    idx=$(( pos * 4 + b + 1 ))
                    if (( idx > n )); then
                        __pyi_err "-L $tok: ikp points at index $idx, but this library (v$PYI_LIB_VERSION) has only $n entries. Is your copy of pyp.sh older than the one this ikp was made for?"
                        return 1
                    fi
                    lib_flag[idx]=1; found=1
                fi
            done
        done
        if (( ! found )); then __pyi_err "-L '$tok': this ikp selects nothing."; return 1; fi
    else
        __pyi_err "-L '$tok' is not valid: use a plain number for ONE index (e.g. 3) or 0x-prefixed hex for an ikp (e.g. 0x15)."
        return 1
    fi
}

__pyi_resolve_lib() {   # lib_tokens -> lib_sel (ascending, unique)
    local t
    for t in "${lib_tokens[@]}"; do __pyi_decode_token "$t" || return 1; done
    lib_sel=("${!lib_flag[@]}")
}

__pyi_list_lib() {
    local n=${#__pyi_LIB[@]} i entry name cat desc namew=7 f=${list_filter,,} shown=0 blk wt maxd
    for entry in "${__pyi_LIB[@]}"; do name=${entry%%|*}; (( ${#name} > namew )) && namew=${#name}; done
    if (( list_md )); then
        echo "| Index | Block | Weight | Package | Category | Description |"
        echo "|------:|------:|-------:|---------|----------|-------------|"
    else
        printf '%s%s%s\n' "$BD" "pyp library v${PYI_LIB_VERSION} - ${n} packages" "$Z"
        printf '%s%5s %5s %6s  %-*s  %-10s %s%s\n' "$D" INDEX BLOCK WEIGHT "$namew" PACKAGE CATEGORY DESCRIPTION "$Z"
    fi
    for (( i = 1; i <= n; i++ )); do
        entry=${__pyi_LIB[i-1]}
        if [[ -n $f && ${entry,,} != *"$f"* ]]; then continue; fi
        IFS='|' read -r name cat desc <<<"$entry"
        blk=$(( (i - 1) / 4 )); wt=$(( 1 << ((i - 1) % 4) ))
        if (( list_md )); then
            printf '| %d | %d | %d | %s | %s | %s |\n' "$i" "$blk" "$wt" "$name" "$cat" "$desc"
        else
            maxd=$(( cols - namew - 34 )); (( maxd < 10 )) && maxd=10
            (( ${#desc} > maxd )) && desc="${desc:0:maxd-3}..."
            printf '%s%5d%s %5d %6d  %s%-*s%s  %-10s %s%s%s\n' "$C" "$i" "$Z" "$blk" "$wt" "$BD" "$namew" "$name" "$Z" "$cat" "$D" "$desc" "$Z"
        fi
        shown=$(( shown + 1 ))
    done
    if (( shown == 0 )); then echo "No library entry matches '$list_filter'." >&2; return 1; fi
    (( list_md )) || printf '%s%d of %d shown. Single package: -L <index>. Several: -L 0x<ikp> (see --help).%s\n' "$D" "$shown" "$n" "$Z"
    return 0
}

__pyi_on_signal() {
    interrupted=1
    [[ -n ${child:-} ]] && kill "$child" 2>/dev/null
}

# ----------------------------------------------------------------------------
# main driver: owns traps, temp dir, cursor and job-control restoration
# ----------------------------------------------------------------------------
__pyi_main() {
    local sourced=$1; shift
    local work child="" interrupted=0 had_m=0 log_file="" log_is_temp=0 rc=0
    local animate=0

    work=$(mktemp -d 2>/dev/null) || { echo "error: cannot create temp dir" >&2; return 1; }
    [[ $- == *m* ]] && { had_m=1; set +m; }          # silence "[1] 1234" job notices
    trap __pyi_on_signal INT TERM

    __pyi_run "$sourced" "$@"
    rc=$?

    (( animate )) && printf '\033[?25h'
    trap - INT TERM
    (( had_m )) && set -m
    rm -rf "$work"
    return $rc
}

__pyi_run() {
    local sourced=$1; shift

    # ---- defaults ------------------------------------------------------
    local req_file="requirements.txt" req_explicit=0 env_dir="myenv" py_cmd=""
    local no_install_python=0 py_requested="" py_found="" py_problem="" crc=0
    local spin_label="" bar_done=0 bar_total=0 spin_rc=0 NOW=0 FMT="" BAR_F="" BAR_E=""
    local assume_yes=0 upgrade=0 upgrade_pip=0 fail_fast=0 dry_run=0 recreate=0
    local quiet=0 verbose=0 color=1 activate=1
    local log_keep="" freeze_file="" report_file=""
    local -a cli_pkgs=() packages=() global_opts=()
    local parse_errors=0 a k
    local -a lib_tokens=() lib_sel=() lib_flag=()
    local list_lib=0 list_filter="" list_md=0

    # ---- argument parsing ---------------------------------------------
    local -a args=()
    for a in "$@"; do                              # expand clusters like -yq
        if [[ $a =~ ^-[yufnRqv]{2,}$ ]]; then
            for (( k = 1; k < ${#a}; k++ )); do args+=("-${a:k:1}"); done
        else
            args+=("$a")
        fi
    done
    set -- "${args[@]}"

    # colors are decided after parsing, but errors may happen before: neutral defaults
    local R="" G="" Y="" C="" D="" BD="" Z="" S_FAIL="x" S_WARN="!"

    while (( $# )); do
        case $1 in
            -h|--help)         __pyi_usage; return 0 ;;
            -V|--version)      echo "pyp $PYI_VERSION"; return 0 ;;
            -r|--requirements) __pyi_need "$@" || return 2; req_file=$2; req_explicit=1; shift ;;
            --requirements=*)  req_file=${1#*=}; req_explicit=1 ;;
            -e|--env)          __pyi_need "$@" || return 2; env_dir=$2; shift ;;
            --env=*)           env_dir=${1#*=} ;;
            -p|--python)       __pyi_need "$@" || return 2; py_cmd=$2; shift ;;
            --python=*)        py_cmd=${1#*=} ;;
            -l|--log)          __pyi_need "$@" || return 2; log_keep=$2; shift ;;
            --log=*)           log_keep=${1#*=} ;;
            --freeze)          __pyi_need "$@" || return 2; freeze_file=$2; shift ;;
            --freeze=*)        freeze_file=${1#*=} ;;
            --report)          __pyi_need "$@" || return 2; report_file=$2; shift ;;
            --report=*)        report_file=${1#*=} ;;
            -L|--lib)          __pyi_need "$@" || return 2; __pyi_add_tokens "$2" || return 2; shift ;;
            --lib=*)           __pyi_add_tokens "${1#*=}" || return 2 ;;
            --list-lib)        list_lib=1 ;;
            --filter)          __pyi_need "$@" || return 2; list_filter=$2; shift ;;
            --filter=*)        list_filter=${1#*=} ;;
            --md)              list_md=1 ;;
            -y|--yes)          assume_yes=1 ;;
            -u|--upgrade)      upgrade=1 ;;
            --upgrade-pip)     upgrade_pip=1 ;;
            -R|--recreate)     recreate=1 ;;
            -f|--fail-fast)    fail_fast=1 ;;
            -n|--dry-run)      dry_run=1 ;;
            --no-activate)     activate=0 ;;
            --no-install-python) no_install_python=1 ;;
            -q|--quiet)        quiet=1 ;;
            -v|--verbose)      verbose=1 ;;
            --no-color)        color=0 ;;
            --)                shift; cli_pkgs+=("$@"); break ;;
            -*)                printf 'error: unknown option: %s (see --help)\n' "$1" >&2; return 2 ;;
            *)                 cli_pkgs+=("$1") ;;
        esac
        shift
    done

    # ---- terminal capabilities / colors / symbols ----------------------
    local is_tty=0
    [[ -t 1 ]] && is_tty=1
    (( is_tty && ! quiet )) && [[ ${TERM:-dumb} != dumb ]] && animate=1

    if (( color )) && (( is_tty )) && [[ -z ${NO_COLOR:-} ]]; then
        R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'
        C=$'\033[36m'; D=$'\033[2m';  BD=$'\033[1m'; Z=$'\033[0m'
    fi
    local utf8=0 loc=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
    [[ $loc == *[Uu][Tt][Ff]*8* ]] && utf8=1
    local S_OK S_SKIP FILL EMPTY H_RULE
    local -a SPIN
    if (( utf8 )); then
        S_OK="✔"; S_FAIL="✘"; S_WARN="!"; S_SKIP="●"; FILL="█"; EMPTY="░"; H_RULE="─"
        SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    else
        S_OK="+"; S_FAIL="x"; S_WARN="!"; S_SKIP="="; FILL="#"; EMPTY="."; H_RULE="-"
        SPIN=('|' '/' '-' '\')
    fi
    local cols=${COLUMNS:-0}
    (( cols > 0 )) || cols=$(tput cols 2>/dev/null || echo 80)

    if (( list_lib )); then __pyi_list_lib; return $?; fi

    # ---- collect packages ----------------------------------------------
    local from_file=0 n_file=0 n_lib=0 n_cli=0 n_dup=0 idx p name ver
    if (( req_explicit )) || (( ${#cli_pkgs[@]} == 0 && ${#lib_tokens[@]} == 0 )); then
        if (( req_explicit )) || [[ -f $req_file ]]; then
            __pyi_parse_req "$req_file" 0
            from_file=1
        fi
    fi
    (( parse_errors )) && return 2
    n_file=${#packages[@]}

    if (( ${#lib_tokens[@]} )); then
        __pyi_resolve_lib || return 2
        for idx in "${lib_sel[@]}"; do packages+=("${__pyi_LIB[idx-1]%%|*}"); done
        n_lib=${#lib_sel[@]}
    fi
    if (( ${#cli_pkgs[@]} )); then packages+=("${cli_pkgs[@]}"); n_cli=${#cli_pkgs[@]}; fi

    local -a uniq=(); local -A seen=()          # drop exact duplicates
    for p in "${packages[@]}"; do
        if [[ -n ${seen[$p]:-} ]]; then n_dup=$(( n_dup + 1 )); else seen[$p]=1; uniq+=("$p"); fi
    done
    packages=("${uniq[@]}")

    if (( ${#packages[@]} == 0 )); then
        if (( from_file )); then
            __pyi_err "'$req_file' was found but contains no packages."
        else
            __pyi_err "No packages specified and no '$req_file' found in this directory."
            echo "Usage: pyp.sh [options] <package ...> | -L <index|ikp>   (see --help)" >&2
        fi
        return 2
    fi
    local total=${#packages[@]}

    # ---- header ---------------------------------------------------------
    __pyi_say "${BD}pyp ${PYI_VERSION}${Z}"
    (( from_file )) && __pyi_say "  ${D}Requirements:${Z} $req_file ($n_file package(s))"
    (( n_lib > 0 ))  && __pyi_say "  ${D}Library:     ${Z} -L ${lib_tokens[*]}  ->  $n_lib package(s) ${D}(library v${PYI_LIB_VERSION}, ${#__pyi_LIB[@]} entries)${Z}"
    (( n_cli > 0 ))  && __pyi_say "  ${D}Packages:    ${Z} $n_cli from command line"
    (( n_dup > 0 ))  && __pyi_say "  ${D}Duplicates:  ${Z} $n_dup skipped"
    __pyi_say "  ${D}Environment: ${Z} $env_dir"

    if (( n_lib > 0 )) && (( ! quiet )); then       # show the decoded selection so an ikp can be checked
        __pyi_say "  ${D}Decoded selection:${Z}"
        local ldesc
        for idx in "${lib_sel[@]}"; do
            IFS='|' read -r name _ ldesc <<<"${__pyi_LIB[idx-1]}"
            printf '    %s[%d]%s %s%s%s %s- %s%s\n' "$C" "$idx" "$Z" "$BD" "$name" "$Z" "$D" "$ldesc" "$Z"
        done
    fi

    # ---- python: detect (installation happens after confirmation) -------
    py_requested=$py_cmd
    __pyi_find_python
    local py_why=""
    if [[ -z $py_found ]]; then
        case $py_problem in
            old)    py_why="no usable Python 3.8+ was found" ;;
            novenv) py_why="Python is installed but its venv/pip support is missing" ;;
            *)      py_why="Python is not installed" ;;
        esac
        __pyi_say "  ${D}Python:      ${Z} ${Y}${py_why}${Z}"
    else
        __pyi_say "  ${D}Python:      ${Z} $("$py_found" --version 2>&1 </dev/null) ($(command -v "$py_found"))"
    fi

    if (( dry_run )); then
        __pyi_say ""
        __pyi_say "${Y}Dry run${Z} - nothing will be changed."
        [[ -z $py_found ]] && __pyi_say "Would install Python first (${py_why})."
        __pyi_say "Would install:"
        local p
        (( ${#global_opts[@]} )) && __pyi_say "  ${D}pip options: ${global_opts[*]}${Z}"
        for p in "${packages[@]}"; do __pyi_say "  ${C}${S_SKIP}${Z} $p"; done
        return 0
    fi

    # ---- confirmation (only when reading a requirements file) -----------
    if (( (from_file || n_lib > 0) && ! assume_yes )); then
        __pyi_say ""
        __pyi_confirm "Install ${total} package(s)? (y/N): "; crc=$?
        if (( crc == 2 )); then
            __pyi_err "No terminal available for the prompt; pass -y/--yes to confirm."
            return 2
        elif (( crc != 0 )); then
            echo "Installation aborted."
            return 1
        fi
    fi

    # ---- python: install if needed --------------------------------------
    if [[ -z $py_found ]]; then
        if [[ -n $py_requested ]]; then
            __pyi_err "Requested interpreter '$py_requested' is not usable (${py_why})."
            return 1
        fi
        if (( no_install_python )); then
            __pyi_err "${py_why}. Install it manually or drop --no-install-python."
            return 1
        fi
        if (( ! assume_yes )); then
            __pyi_confirm "  Install Python now? (y/N): "; crc=$?
            if (( crc == 2 )); then
                __pyi_err "${py_why}; no terminal for a prompt. Pass -y/--yes to allow installing it."
                return 2
            elif (( crc != 0 )); then
                echo "Python is required. Aborted."
                return 1
            fi
        fi
        __pyi_install_python || return 1
        (( interrupted )) && return 130
        __pyi_find_python
        if [[ -z $py_found ]]; then
            __pyi_err "Python was installed but is not usable in this shell yet. Open a new terminal and run again."
            return 1
        fi
        __pyi_say "  ${G}${S_OK}${Z} Python installed: $("$py_found" --version 2>&1 </dev/null) ($(command -v "$py_found"))"
    fi
    py_cmd=$py_found
    __pyi_say ""

    # ---- combined log location -----------------------------------------
    if [[ -n $log_keep ]]; then log_file=$log_keep
    else log_file="${TMPDIR:-/tmp}/pyp-$$.log"; log_is_temp=1; fi
    : > "$log_file" 2>/dev/null || { __pyi_err "Cannot write log file: $log_file"; return 1; }

    # ---- virtual environment -------------------------------------------

    if (( recreate )) && [[ -e $env_dir ]]; then
        case $env_dir in ""|/|.|..|~|"$HOME") __pyi_err "Refusing to delete '$env_dir'."; return 1 ;; esac
        if [[ ! -f $env_dir/pyvenv.cfg ]]; then
            __pyi_err "'$env_dir' is not a virtualenv (no pyvenv.cfg); refusing to delete it."; return 1
        fi
        rm -rf "$env_dir"
    fi

    local env_state="reused"
    if [[ ! -f $env_dir/pyvenv.cfg ]]; then
        if [[ -e $env_dir && -n "$(ls -A "$env_dir" 2>/dev/null)" ]]; then
            __pyi_err "'$env_dir' exists but is not a virtualenv. Choose another --env."; return 1
        fi
        env_state="created"
        spin_label="Creating virtual environment '$env_dir'"
        __pyi_now; local t_env=$NOW
        __pyi_spin "$work/venv.log" "$py_cmd" -m venv "$env_dir"
        if (( spin_rc == 130 )); then __pyi_say "${Y}Interrupted.${Z}"; return 130; fi
        if (( spin_rc != 0 )); then
            __pyi_err "Virtual environment creation failed:"
            sed 's/^/    /' "$work/venv.log" >&2
            echo "  Hint: on Debian/Ubuntu install it with: sudo apt install python3-venv" >&2
            return 1
        fi
        __pyi_now; __pyi_fmt_ms $(( NOW - t_env ))
        __pyi_say "  ${G}${S_OK}${Z} Virtual environment created ${D}($FMT)${Z}"
    else
        __pyi_say "  ${G}${S_OK}${Z} Using existing virtual environment"
    fi

    local venv_py="$env_dir/bin/python" venv_activate="$env_dir/bin/activate"
    if [[ ! -x $venv_py ]]; then venv_py="$env_dir/Scripts/python.exe"; venv_activate="$env_dir/Scripts/activate"; fi
    if [[ ! -x $venv_py ]]; then __pyi_err "Cannot find python inside '$env_dir'."; return 1; fi

    if (( upgrade_pip )); then
        spin_label="Upgrading pip"
        __pyi_spin "$work/pip.log" "$venv_py" -m pip install --disable-pip-version-check --no-input --upgrade pip
        if (( spin_rc == 0 )); then __pyi_say "  ${G}${S_OK}${Z} pip upgraded"
        else __pyi_warn "pip upgrade failed (continuing)"; fi
    fi

    # ---- install loop ---------------------------------------------------
    local n_inst=0 n_uptodate=0 n_fail=0 n_skip=0 spec plog extra
    local -a failed_names=() failed_msgs=() cmd extra_args pkgs_arr
    local namew=10 t_all t_pkg line re succ_line msg
    for spec in "${packages[@]}"; do
        name=$(__pyi_name "$spec"); (( ${#name} > namew )) && namew=${#name}
    done
    (( namew > 30 )) && namew=30
    (( cols - 40 < namew )) && namew=$(( cols - 40 > 10 ? cols - 40 : 10 ))

    __pyi_say "${BD}Installing ${total} package(s)${Z}"
    __pyi_now; t_all=$NOW
    bar_total=$total

    for (( idx = 0; idx < total; idx++ )); do
        (( interrupted )) && break
        spec=${packages[idx]}
        name=$(__pyi_name "$spec")
        plog="$work/pkg_$idx.log"
        bar_done=$idx
        spin_label="Installing $name"

        cmd=("$venv_py" -m pip install --disable-pip-version-check --no-input --progress-bar off)
        (( ${#global_opts[@]} )) && cmd+=("${global_opts[@]}")
        (( upgrade )) && cmd+=(--upgrade)
        if [[ $spec == -* ]]; then read -ra extra_args <<<"$spec"; cmd+=("${extra_args[@]}")
        else cmd+=("$spec"); fi

        __pyi_now; t_pkg=$NOW
        __pyi_spin "$plog" "${cmd[@]}"
        __pyi_now; __pyi_fmt_ms $(( NOW - t_pkg ))
        { printf '=== %s  (exit %s) ===\n' "$spec" "$spin_rc"; cat "$plog"; echo; } >> "$log_file"

        if (( spin_rc == 130 )); then interrupted=1; break; fi

        ver=""; extra=""
        if (( spin_rc == 0 )); then
            re=${name//[-_.]/[-_.]}
            succ_line=$(grep -m1 '^Successfully installed' "$plog")
            if [[ -n $succ_line ]]; then
                n_inst=$(( n_inst + 1 ))
                read -ra pkgs_arr <<<"${succ_line#Successfully installed }"
                ver=$(printf '%s\n' "${pkgs_arr[@]}" | grep -iE -m1 "^${re}-[0-9]" | sed -E 's/^.*-([0-9][^-]*)$/\1/')
                (( ${#pkgs_arr[@]} > 1 )) && extra="+$(( ${#pkgs_arr[@]} - 1 )) deps  "
                (( quiet )) || printf '  %s%s%s %-*s %-12s %s%s%s%s\n' "$G" "$S_OK" "$Z" "$namew" "$name" "$ver" "$D" "$extra" "$FMT" "$Z"
            else
                n_uptodate=$(( n_uptodate + 1 ))
                ver=$(grep -iE -m1 "^Requirement already satisfied: ${re}( |\[|==|<|>|!|~)" "$plog" | sed -nE 's/.*\(([^)]*)\)$/\1/p')
                (( quiet )) || printf '  %s%s%s %-*s %-12s %salready satisfied  %s%s\n' "$C" "$S_SKIP" "$Z" "$namew" "$name" "$ver" "$D" "$FMT" "$Z"
            fi
        else
            n_fail=$(( n_fail + 1 ))
            msg=$(grep '^ERROR:' "$plog" | tail -n1); msg=${msg#ERROR: }
            [[ -z $msg ]] && msg=$(grep -v '^[[:space:]]*$' "$plog" | tail -n1)
            [[ -z $msg ]] && msg="pip exited with code $spin_rc"
            failed_names+=("$spec"); failed_msgs+=("$msg")
            local short=$msg maxm=$(( cols - namew - 22 )); (( maxm < 20 )) && maxm=20
            (( ${#short} > maxm )) && short="${short:0:maxm-3}..."
            (( quiet )) || printf '  %s%s%s %-*s %s%s%s %s(%s)%s\n' "$R" "$S_FAIL" "$Z" "$namew" "$name" "$R" "$short" "$Z" "$D" "$FMT" "$Z"
        fi
        if (( verbose && ! quiet )); then sed "s/^/      ${D}|${Z} /" "$plog"; fi

        if (( fail_fast && n_fail > 0 )); then
            n_skip=$(( total - idx - 1 )); break
        fi
    done
    (( interrupted )) && n_skip=$(( total - n_inst - n_uptodate - n_fail ))

    __pyi_now; __pyi_fmt_ms $(( NOW - t_all )); local total_time=$FMT
    local done_count=$(( n_inst + n_uptodate + n_fail ))
    local n_ok=$(( n_inst + n_uptodate ))

    # ---- freeze ---------------------------------------------------------
    if [[ -n $freeze_file ]] && (( ! interrupted )); then
        if "$venv_py" -m pip freeze > "$freeze_file" 2>"$work/freeze.log" </dev/null; then
            __pyi_say "  ${G}${S_OK}${Z} Wrote freeze file: $freeze_file"
        else
            __pyi_warn "pip freeze failed: $(tail -n1 "$work/freeze.log")"
        fi
    fi

    # ---- summary --------------------------------------------------------
    local colr=$G; (( n_fail > 0 )) && colr=$Y; (( n_ok == 0 && n_fail > 0 )) && colr=$R
    local rule; printf -v rule '%*s' 44 ''; rule=${rule// /$H_RULE}
    local pct=0; (( total > 0 )) && pct=$(( n_ok * 100 / total ))
    __pyi_bar "$n_ok" "$total" 30

    if (( quiet )); then
        printf '%s: %d installed, %d up-to-date, %d failed, %d skipped (%s)\n' \
            "pyp" "$n_inst" "$n_uptodate" "$n_fail" "$n_skip" "$total_time"
        local i
        for i in "${!failed_names[@]}"; do
            printf '  %s %s: %s\n' "$S_FAIL" "${failed_names[i]}" "${failed_msgs[i]}"
        done
    else
        echo
        echo "${BD}${rule}${Z}"
        echo "${BD} Summary${Z}"
        echo "${BD}${rule}${Z}"
        printf '  %s[%s%s%s%s]%s %d%% succeeded\n' "$colr" "$BAR_F" "$D" "$BAR_E" "$colr" "$Z" "$pct"
        echo
        printf '  %s%s%s Installed     %s%d%s\n'  "$G" "$S_OK"   "$Z" "$BD" "$n_inst"     "$Z"
        printf '  %s%s%s Up-to-date    %s%d%s\n'  "$C" "$S_SKIP" "$Z" "$BD" "$n_uptodate" "$Z"
        printf '  %s%s%s Failed        %s%d%s\n'  "$R" "$S_FAIL" "$Z" "$BD" "$n_fail"     "$Z"
        (( n_skip > 0 )) && printf '  %s%s%s Not attempted %s%d%s\n' "$Y" "$S_WARN" "$Z" "$BD" "$n_skip" "$Z"
        printf '  %sTotal         %d package(s) in %s%s\n' "$D" "$total" "$total_time" "$Z"
        if (( n_fail > 0 )); then
            echo
            echo "${R}${BD}Failed packages:${Z}"
            local i
            for i in "${!failed_names[@]}"; do
                printf '  %s%s%s %s\n      %s%s%s\n' "$R" "$S_FAIL" "$Z" "${failed_names[i]}" "$D" "${failed_msgs[i]}" "$Z"
            done
            echo
            echo "  ${D}Full pip output: $log_file${Z}"
        fi
    fi

    # ---- plain-text report file ----------------------------------------
    if [[ -n $report_file ]]; then
        {
            echo "pyp $PYI_VERSION report - $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Environment : $env_dir ($env_state)"
            echo "Python      : $("$py_cmd" --version 2>&1 </dev/null)"
            echo "Packages    : $total"
            echo "Installed   : $n_inst"
            echo "Up-to-date  : $n_uptodate"
            echo "Failed      : $n_fail"
            echo "Not tried   : $n_skip"
            echo "Duration    : $total_time"
            local i
            for i in "${!failed_names[@]}"; do echo "FAILED: ${failed_names[i]} -> ${failed_msgs[i]}"; done
        } > "$report_file" 2>/dev/null && __pyi_say "  ${D}Report written to $report_file${Z}"
    fi

    # ---- activation / hints --------------------------------------------
    local exit_code=0
    (( n_fail > 0 )) && exit_code=1
    (( interrupted )) && { exit_code=130; echo "${Y}${S_WARN} Interrupted - ${done_count}/${total} processed.${Z}"; }

    if (( n_fail == 0 && ! interrupted )) || (( n_ok > 0 )); then
        if (( activate )) && (( sourced )); then
            # shellcheck disable=SC1090
            source "$venv_activate" && __pyi_say "  ${G}${S_OK}${Z} Environment activated: ${BD}$env_dir${Z}"
        elif (( ! sourced )); then
            local psh act_file=$venv_activate        # which shell launched us? show ITS activate script
            psh=$(ps -o comm= -p "$PPID" 2>/dev/null); psh=${psh##*/}; psh=${psh#-}
            case $psh in
                fish)     act_file="${venv_activate}.fish" ;;
                csh|tcsh) act_file="${venv_activate}.csh" ;;
            esac
            if [[ $psh == fish || $psh == csh || $psh == tcsh ]]; then
                __pyi_say "  ${D}Activate with:${Z} source $act_file"
            else
                __pyi_say "  ${D}Activate with:${Z} source $act_file   ${D}(or launch this script with: source <(curl -fsSL $PYI_RAW_URL) ...)${Z}"
            fi
        fi
    fi

    (( log_is_temp && n_fail == 0 )) && rm -f "$log_file"
    return $exit_code
}

# ----------------------------------------------------------------------------
# entry point
# ----------------------------------------------------------------------------
__pyi_sourced=0
(return 0 2>/dev/null) && __pyi_sourced=1

__pyi_main "$__pyi_sourced" "$@"
__pyi_rc=$?

if (( __pyi_sourced )); then
    # leave no helpers or variables behind in the user's shell
    eval "unset __pyi_rc __pyi_sourced PYI_VERSION PYI_LIB_VERSION PYI_RAW_URL __pyi_LIB; \
          unset -f __pyi_usage __pyi_err __pyi_warn __pyi_say __pyi_need __pyi_now \
                   __pyi_fmt_ms __pyi_bar __pyi_name __pyi_draw __pyi_spin \
                   __pyi_parse_req __pyi_on_signal __pyi_main __pyi_run \
                   __pyi_confirm __pyi_fetch __pyi_find_python __pyi_install_python \
                   __pyi_add_tokens __pyi_decode_token __pyi_resolve_lib __pyi_list_lib; \
          return $__pyi_rc"
else
    exit "$__pyi_rc"
fi
