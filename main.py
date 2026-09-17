import sys
from src.cli import main as cli_main

def main():
    if len(sys.argv) == 1:
        # Show help if no arguments provided
        sys.argv.append("--help")
    cli_main()

if __name__ == "__main__":
    main()
