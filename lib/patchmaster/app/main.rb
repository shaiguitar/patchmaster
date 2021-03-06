require 'curses'
require 'singleton'
%w(list patch info trigger prompt).each { |w| require "patchmaster/app/#{w}_window" }

module PM

class Main

  include Singleton
  include Curses

  FUNCTION_KEY_SYMBOLS = {}
  12.times do |i|
    FUNCTION_KEY_SYMBOLS["f#{i+1}".to_sym] = Key::F1 + i
    FUNCTION_KEY_SYMBOLS["F#{i+1}".to_sym] = Key::F1 + i
  end

  def initialize
    @pm = PatchMaster.instance
    @message_bindings = {}
  end

  def no_midi!
    @pm.no_midi!
  end

  def run
    @pm.start
    begin
      config_curses
      create_windows

      loop do
        begin
          refresh_all
          ch = getch
          message("ch = #{ch}") if $DEBUG
          case ch
          when 'j', Key::DOWN, ' '
            @pm.next_patch
          when 'k', Key::UP
            @pm.prev_patch
          when 'n', Key::LEFT
            @pm.next_song
          when 'p', Key::RIGHT
            @pm.prev_song
          when 'g'
            name = PromptWindow.new('Go To Song', 'Go to song:').gets
            @pm.goto_song(name)
          when 't'
            name = PromptWindow.new('Go To Song List', 'Go to Song List:').gets
            @pm.goto_song_list(name)
          when 'e'
            close_screen
            file = @loaded_file || PromptWindow.new('Edit', 'Edit file:').gets
            edit(file)
          when 'h'
            help
          when 27        # "\e" doesn't work here
            # Twice in a row sends individual note-off commands
            message('Sending panic note off messages...')
            @pm.panic(@prev_cmd == 27)
            message('Panic sent')
          when 'l'
            file = PromptWindow.new('Load', 'Load file:').gets
            begin
              load(file)
              message("Loaded #{file}")
            rescue => ex
              message(ex.to_s)
            end
          when 's'
            file = PromptWindow.new('Save', 'Save into file:').gets
            begin
              save(file)
              message("Saved #{file}")
            rescue => ex
              message(ex.to_s)
            end
          when '?'
            if $DEBUG
              require 'pp'
              out = ''
              str = pp(@pm, out)
              message("pm = #{out}")
            end
          when 'q'
            break
          end
          @prev_cmd = ch
        rescue => ex
          message(ex.to_s)
          @pm.debug caller.join("\n")
        end

        msg_name = @message_bindings[ch]
        @pm.send_message(msg_name) if msg_name
      end
    ensure
      clear
      refresh
      close_screen
      @pm.stop
      @pm.close_debug_file
    end
  end

  def bind_message(name, key_or_sym)
    if FUNCTION_KEY_SYMBOLS.keys.include?(key_or_sym)
      @message_bindings[FUNCTION_KEY_SYMBOLS[key_or_sym]] = name
    else
      @message_bindings[key_or_sym] = name
    end
  end

  def config_curses
    init_screen
    cbreak                      # unbuffered input
    noecho                      # do not show typed keys
    stdscr.keypad(true)         # enable arrow keys
    curs_set(0)                 # cursor: 0 = invisible, 1 = normal
  end

  def create_windows
    top_height = (lines() - 1) * 2 / 3
    bot_height = (lines() - 1) - top_height
    top_width = cols() / 3

    sls_height = top_height / 3
    sl_height = top_height - sls_height
    
    @song_lists_win = ListWindow.new(sls_height, top_width, 0, 0, nil)
    @song_list_win = ListWindow.new(sl_height, top_width, sls_height, 0, 'Song List')
    @song_win = ListWindow.new(top_height, top_width, 0, top_width, 'Song')
    @patch_win = PatchWindow.new(bot_height, cols(), top_height, 0, 'Patch')
    @message_win = Window.new(1, cols(), lines()-1, 0)
    @message_win.scrollok(false)

    third_height = top_height / 3
    width = cols() - (top_width * 2) - 1
    left = top_width * 2 + 1

    @trigger_win = TriggerWindow.new(third_height, width, third_height * 2, left)
    @trigger_win.draw

    @info_win = InfoWindow.new(third_height * 2, width, 0, left)
    @info_win.draw

  end

  def load(file)
    @pm.load(file)
    @loaded_file = file
  end

  def save(file)
    @pm.save(file)
    @loaded_file = file
  end

  # Opens the most recently loaded/saved file name in an editor. After
  # editing, the file is re-loaded.
  def edit(file)
    editor_command = find_editor
    unless editor_command
      message("Can not find $VISUAL, $EDITOR, vim, or vi on your path")
      return
    end

    cmd = "#{editor_command} #{file}"
    @pm.debug(cmd)
    system(cmd)
    load(file)
    @loaded_file = file
  end

  # Return the first legit command from $VISUAL, $EDITOR, vim, vi, and
  # notepad.exe.
  def find_editor
    @editor ||= [ENV['VISUAL'], ENV['EDITOR'], 'vim', 'vi', 'notepad.exe'].compact.detect do |cmd|
      system('which', cmd) || File.exist?(cmd)
    end
  end

  def help
    message("Help: not yet implemented")
  end

  def message(str)
    if @message_win
      @message_win.clear
      @message_win.addstr(str)
      @message_win.refresh
    else
      $stderr.puts str
    end
    @pm.debug "#{Time.now} #{str}"
  end

  def refresh_all
    set_window_data
    wins = [@song_lists_win, @song_list_win, @song_win, @patch_win, @info_win, @trigger_win]
    wins.map(&:draw)
    ([stdscr] + wins).map(&:refresh)
  end

  def set_window_data
    @song_lists_win.set_contents('Song Lists', @pm.song_lists, :song_list)

    song_list = @pm.song_list
    @song_list_win.set_contents(song_list.name, song_list.songs, :song)

    song = @pm.song
    if song
      @song_win.set_contents(song.name, song.patches, :patch)
      patch = @pm.patch
      @patch_win.patch = patch
    else
      @song_win.set_contents(nil, nil, :patch)
      @patch_win.patch = nil
    end
  end

end
end
