require 'ver/ncurses'
module VER
  # Responsibilities:
  # * Interface to Ncurses::WINDOW and Ncurses::Panel
  # * behave IO like: (print puts write read readline)
  # * hide and show itself

  # There's a very strange bug when i tried subclassing this, as Ncurses seems
  # to overwrite WINDOW::new, which will not return the Window instance we
  # want. So we have to wrap instead of subclass.
  class Window # < Ncurses::WINDOW
    attr_reader :width, :height, :top, :left
    attr_accessor :layout
    attr_reader   :panel   # XXX reader requires so he can del it in end

    def initialize(layout)
      @visible = true
      reset_layout(layout)

      @window = Ncurses::WINDOW.new(height, width, top, left)
      @panel = Ncurses::Panel.new_panel(@window)
      ## eeks XXX next line will wreak havoc when multiple windows opened like a mb or popup
      $error_message_row = $status_message_row = Ncurses.LINES-1

      Ncurses::keypad(@window, true)
      @stack = []
    end
    def self.root_window(layout = { :height => 0, :width => 0, :top => 0, :left => 0 })
      #VER::start_ncurses
      @layout = layout
      @window = Window.new(@layout)
      @window.wrefresh
      Ncurses::Panel.update_panels
      return @window
    end

    def resize_with(layout)
      reset_layout(layout)
      @window.wresize(height, width)
      @window.mvwin(top, left)
    end

    %w[width height top left].each do |side|
      eval(
      "def #{side}=(n)
         return if n == #{side}
         @layout[:#{side}] = n
         resize_with @layout
       end"
      )
    end

    def resize
      resize_with(@layout)
    end

    # Ncurses

    def pos
      return y, x
    end

    def y
      Ncurses.getcury(@window)
    end

    def x
      Ncurses.getcurx(@window)
    end

    def x=(n) move(y, n) end
    def y=(n) move(n, x) end

    def move(y, x)
      return unless @visible
#       Log.debug([y, x] => caller[0,4])
      @window.move(y, x)
    end

    def method_missing(meth, *args)
      @window.send(meth, *args)
    end

    def print(string, width = width)
      return unless visible?
      @window.waddnstr(string.to_s, width)
    end

    def print_yx(string, y = 0, x = 0)
      @window.mvwaddnstr(y, x, string, width)
    end

    def print_empty_line
      return unless visible?
      @window.printw(' ' * width)
    end

    def print_line(string)
      print(string.ljust(width))
    end

    def show_colored_chunks(chunks)
      return unless visible?
      chunks.each do |color, chunk|
        color_set(color)
        print_line(chunk)
      end
    end

    def puts(*strings)
      print(strings.join("\n") << "\n")
    end

    def refresh
      return unless visible?
      @window.refresh
    end

    def wnoutrefresh
      return unless visible?
      @window.wnoutrefresh
    end

    def color=(color)
      @color = color
      @window.color_set(color, nil)
    end

    def highlight_line(color, y, x, max)
      @window.mvchgat(y, x, max, Ncurses::A_NORMAL, color, nil)
    end

    def getch
      @window.getch
    rescue Interrupt => ex
      3 # is C-c
    end

    # returns control, alt, alt+ctrl, alt+control+shift, F1 .. etc
    # ALT combinations also send a 27 before the actual key
    # Please test with above combinations before using on your terminal
    # added by rkumar 2008-12-12 23:07 
    def getchar 
      while 1 
        ch = getch
        #$log.debug "window getchar() GOT: #{ch}" if ch != -1
        if ch == -1
          # the returns escape 27 if no key followed it, so its SLOW if you want only esc
          if @stack.first == 27
            #$log.debug " -1 stack sizze #{@stack.size}: #{@stack.inspect}, ch #{ch}"
            case @stack.size
            when 1
              @stack.clear
              return 27
            when 2 # basically a ALT-O, this will be really slow since it waits for -1
              ch = 128 + @stack.last
              @stack.clear
              return ch
            when 3
              $log.debug " SHOULD NOT COME HERE getchar()"
            end
          end
          @stack.clear
          next
        end
        # this is the ALT combination
        if @stack.first == 27
          # experimental. 2 escapes in quick succession to make exit faster
          if ch == 27
            @stack.clear
            return ch
          end
          # possible F1..F3 on xterm-color
          if ch == 79 or ch == 91
            #$log.debug " got 27, #{ch}, waiting for one more"
            @stack << ch
            next
          end
          #$log.debug "stack SIZE  #{@stack.size}, #{@stack.inspect}, ch: #{ch}"
          if @stack == [27,79]
            # xterm-color
            case ch
            when 80
              ch = KEY_F1
            when 81
              ch = KEY_F2
            when 82
              ch = KEY_F3
            when 83
              ch = KEY_F4
            end
            @stack.clear
            return ch
          elsif @stack == [27, 91]
            if ch == 90
              @stack.clear
              return 353 # backtab
            end
          end
          # the usual Meta combos. (alt)
          ch = 128 + ch
          @stack.clear
          return ch
        end
        # append a 27 to stack, actually one can use a flag too
        if ch == 27
          @stack << 27
          next
        end
        return ch
      end
    end

    def clear
      # return unless visible?
      move 0, 0
      puts *Array.new(height){ ' ' * (width - 1) }
    end

    # setup and reset

    def reset_layout(layout)
      @layout = layout

      [:height, :width, :top, :left].each do |name|
        instance_variable_set("@#{name}", layout_value(name))
      end
    end

    def layout_value(name)
      value = @layout[name]
      default = default_for(name)

      value = value.call(default) if value.respond_to?(:call)
      return (value || default).to_i
    end

    def default_for(name)
      case name
      when :height, :top
        Ncurses.stdscr.getmaxy
      when :width, :left
        Ncurses.stdscr.getmaxx
      else
        0
      end
    end

    # Ncurses panel

    def hide
      Ncurses::Panel.hide_panel @panel
      Ncurses.refresh # wnoutrefresh
      @visible = false
    end

    def show
      Ncurses::Panel.show_panel @panel
      Ncurses.refresh # wnoutrefresh
      @visible = true
    end

    def on_top
      Ncurses::Panel.top_panel @panel
      wnoutrefresh
    end

    def visible?
      @visible
    end
    ##
    #added by rk 2008-11-29 18:48 
    #to see if we can clean up from within
    def destroy
      # typically the ensure block should have this
      # @panel = @window.panel if @window
      #Ncurses::Panel.del_panel(@panel) if !@panel.nil?   
      #@window.delwin if !@window.nil?

      #@panel = @window.panel if @window
      Ncurses::Panel.del_panel(@panel) if !@panel.nil?   
      @window.delwin if !@window.nil?
    end
    ## 
    # added by rk 2008-11-29 19:01 
    # I usually use this, not the others ones here
    # @param  r - row
    # @param  c - col
    # @param string - text to print
    # @param color - color pair
    # @ param att - ncurses attribute: normal, bold, reverse, blink,
    # underline
    def printstring(r,c,string, color, att = Ncurses::A_NORMAL)

      ## XXX check if row is exceeding height and don't print
      att = Ncurses::A_NORMAL if att.nil?
      case att.to_s.downcase
      when 'underline'
        att = Ncurses::A_UNDERLINE
      when 'bold'
        att = Ncurses::A_BOLD
      when 'blink'
        att = Ncurses::A_BLINK    # unlikely to work
      when 'reverse'
        att = Ncurses::A_REVERSE    
      end

      attron(Ncurses.COLOR_PAIR(color) | att)
      # we should not print beyond window coordinates
      # trying out on 2009-01-03 19:29 
      width = Ncurses.COLS
      # the next line won't ensure we don't write outside some bounds like table
      #string = string[0..(width-c)] if c + string.length > width
      #$log.debug "PRINT #{string.length}, #{Ncurses.COLS}, #{c} "
      mvprintw(r, c, "%s", string);
      attroff(Ncurses.COLOR_PAIR(color) | att)
    end
    # added by rk 2008-11-29 19:01 
    def print_error_message text=$error_message
      r = $error_message_row || Ncurses.LINES-1
      $log.debug "got ERROR MEASSAGE #{text} row #{r} "
      clear_error r, $datacolor
      # print it in centre
      printstring r, (Ncurses.COLS-text.length)/2, text, color = $promptcolor
    end
    # added by rk 2008-11-29 19:01 
    def print_status_message text=$status_message
      r = $status_message_row || Ncurses.LINES-1
      clear_error r, $datacolor
      # print it in centre
      printstring r, (Ncurses.COLS-text.length)/2, text, color = $promptcolor
    end
    # added by rk 2008-11-29 19:01 
    def clear_error r = $error_message_row, color = $datacolor
      printstring(r, 0, "%-*s" % [Ncurses.COLS," "], color)
    end
    def print_border_mb row, col, height, width, color, attr
      mvwaddch row, col, ACS_ULCORNER
      mvwhline( row, col+1, ACS_HLINE, width-6)
      mvwaddch row, col+width-5, Ncurses::ACS_URCORNER
      mvwvline( row+1, col, ACS_VLINE, height-4)

      mvwaddch row+height-3, col, Ncurses::ACS_LLCORNER
      mvwhline(row+height-3, col+1, ACS_HLINE, width-6)
      mvwaddch row+height-3, col+width-5, Ncurses::ACS_LRCORNER
      mvwvline( row+1, col+width-5, ACS_VLINE, height-4)
    end
    def print_border row, col, height, width, color, att=Ncurses::A_NORMAL
      att ||= Ncurses::A_NORMAL

      (row+1).upto(row+height-1) do |r|
        printstring( r, col+1," "*(width-2) , color, att)
      end
      attron(Ncurses.COLOR_PAIR(color) | att)


      mvwaddch row, col, ACS_ULCORNER
      mvwhline( row, col+1, ACS_HLINE, width-2)
      mvwaddch row, col+width-1, Ncurses::ACS_URCORNER
      mvwvline( row+1, col, ACS_VLINE, height-1)

      mvwaddch row+height-0, col, Ncurses::ACS_LLCORNER
      mvwhline(row+height-0, col+1, ACS_HLINE, width-2)
      mvwaddch row+height-0, col+width-1, Ncurses::ACS_LRCORNER
      mvwvline( row+1, col+width-1, ACS_VLINE, height-1)
      attroff(Ncurses.COLOR_PAIR(color) | att)
    end
  end
end
