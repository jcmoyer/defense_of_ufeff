import os
import zipfile
import tempfile
import urllib.request

SDL2_DEVEL = 'https://github.com/libsdl-org/SDL/releases/download/release-2.24.1/SDL2-devel-2.24.1-mingw.zip'

def main():
    os.makedirs("thirdparty", exist_ok=True)

    with tempfile.TemporaryFile() as tf:
        print("Using tempfile: {}".format(tf.name))
        print("GET {}".format(SDL2_DEVEL))
        with urllib.request.urlopen(SDL2_DEVEL) as f:
            tf.write(f.read())
            tf.flush()
        print("Extract to ./thirdparty/")
        with zipfile.ZipFile(tf) as zip:
            zip.extractall("thirdparty")

if __name__ == '__main__':
    main()
