ffmpeg -i "%~1" -codec:a libmp3lame -qscale:a 2 "%~p1%~n1.mp3"
