# Provides the ability to scroll content, typically an array
# widget that includes may override on_enter_row and on_leave_row
# Caller should have
#   row_count()
#   scrollatrow() typically @height - 2 (unless a header row, then -3)
#   @current_index (row of current index, starting with 0 usually)
#   @toprow : set to 0 for starters, top row to be displayed
#   @pcol (used for horiz scrolling, starts at 0)
#
module ListScrollable
  def previous_row
    @oldrow = @current_index
    @current_index -= 1 if @current_index > 0
    bounds_check
  end
  alias :up :previous_row
  def next_row
    @oldrow = @current_index
    rc = row_count
    @current_index += 1 if @current_index < rc
    bounds_check
  end
  alias :down :next_row
  def goto_bottom
    @oldrow = @current_index
    rc = row_count
    @current_index = rc -1
    bounds_check
  end
  alias :goto_end :goto_bottom
  def goto_top
    @oldrow = @current_index
    @current_index = 0
    bounds_check
  end
  alias :goto_start :goto_top
  def scroll_backward
    @oldrow = @current_index
    h = scrollatrow()
    @current_index -= h 
    bounds_check
  end
  def scroll_forward
    @oldrow = @current_index
    h = scrollatrow()
    rc = row_count
    # more rows than box
    if h < rc
      @toprow += h+1 #if @current_index+h < rc
      @current_index = @toprow
    else
      # fewer rows than box
      @current_index = rc -1
    end
    #@current_index += h+1 #if @current_index+h < rc
    bounds_check
  end

  ##
  # please set oldrow before calling this. Store current_index as oldrow before changing. NOTE
  def bounds_check
    h = scrollatrow()
    rc = row_count
    $log.debug " PRE CURR:#{@current_index}, TR: #{@toprow} RC: #{rc} H:#{h}"
    @current_index = 0 if @current_index < 0  # not lt 0
    @current_index = rc-1 if @current_index >= rc # not gt rowcount
    @toprow = rc-h-1 if rc > h and @toprow > rc - h - 1 # toprow shows full page if possible
    # curr has gone below table,  move toprow forward
    if @current_index - @toprow > h
      @toprow = @current_index - h
    elsif @current_index < @toprow
      # curr has gone above table,  move toprow up
      @toprow = @current_index
    end
    #$log.debug " POST CURR:#{@current_index}, TR: #{@toprow} RC: #{rc} H:#{h}"
    if @oldrow != @current_index
      $log.debug "going to call on leave and on enter"
      on_leave_row @oldrow if respond_to? :on_leave_row     # to be defined by widget that has included this
      on_enter_row @current_index   if respond_to? :on_enter_row  # to be defined by widget that has included this
    end
    set_form_row
    @repaint_required = true
  end
  # the cursor should be appropriately positioned
  def set_form_row
    r,c = rowcol
    @form.row = r + (@current_index-@toprow) 
  end
  def right
    @hscrollcols ||= @cols/2
    @pcol += @hscrollcols if @pcol + @hscrollcols < @padcols
    #   window_erase @win XXX
  end
  def left
    @hscrollcols ||= @cols/2
    @pcol -= @hscrollcols if @pcol > 0
    @pcol = 0 if @pcol < 0
  end
  # not that saving content_rows is buggy since we add rows.
  ##
  # caution, this now uses winrow not prow
  ## for user to know which row is being focussed on
  def focussed_index
    @current_index # 2009-01-07 14:35 
  end
  # only to be used in single selection cases as focussed item FIXME.
  # best not to use, as can be implementation dep, use current_index
  def selected_item
    get_content()[focussed_index()]
  end
  #alias :current_index :focussed_index
  alias :selected_index :focussed_index
  def OLDscrollable_handle_key ch
    begin
      ###pre_key # 2009-01-07 13:23 
      case ch
      when ?\C-n
        scroll_forward
      when 32
        scroll_forward
      when ?\C-p
        scroll_backward
      when ?0
        #goto_start
        goto_top
      when ?9
        #goto_end
        goto_bottom
      when KEY_UP
        #select_prev_row
        #up
        $log.debug " GOT KEY UP NEW SCROLL"
        previous_row
      when KEY_LEFT
      when KEY_RIGHT
      when KEY_DOWN
        #down
        $log.debug " GOT KEY DOWN NEW SCROLL"
        next_row
      when KEY_ENTER, 10, 13
        if respond_to? :fire
          fire
        end
      when ?A..?Z, ?a..?z
        ret = set_selection_for_char ch.chr
      else
        return :UNHANDLED #if ret == -1
      end
    ensure
      #post_key
    end
  end # handle_k listb
  ## 2008-12-18 18:03 
  # finds the next match for the char pressed
  # returning the index
  def next_match char
    data = get_content
    row = focussed_index + 1
    row.upto(data.length-1) do |ix|
      val = data[ix].chomp
      #if val[0,1] == char #and val != currval
      if val[0,1].casecmp(char) == 0 #AND VAL != CURRval
        return ix
      end
    end
    row = focussed_index - 1
    0.upto(row) do |ix|
      val = data[ix].chomp
      #if val[0,1] == char #and val != currval
      if val[0,1].casecmp(char) == 0 #and val != currval
        return ix
      end
    end
    return -1
  end
  ## 2008-12-18 18:03 
  # sets the selection to the next row starting with char
  def set_selection_for_char char
    @oldrow = @current_index
    ix = next_match char
    @current_index = ix if ix != -1
    bounds_check
    return ix
  end

  ##
  # ensures that the given row is focussed
  # new version of older one that was not perfect.
  # 2009-01-17 13:25 
  def set_focus_on arow
    @oldrow = @current_index
    @current_index = arow
    bounds_check if @oldrow != @current_index
  end
  ##
  # 2008-12-18 18:05 
  # set focus on given index
  def OLDset_focus_on arow
    return if arow > row_count()-1 or arow < 0
    @oldrow = @current_index
    total = row_count()
    @current_index = arow
    sar = scrollatrow + 1
    @toprow = (@current_index / sar) * sar

    $log.debug "1 set_focus #{total}, sar #{sar}, toprow #{@toprow}, current_index #{@current_index}"
    if total - @toprow < sar
      @toprow = (total - sar) 
    end
    $log.debug "2 set_focus #{total}, sar #{sar}, toprow #{@toprow}, current_index #{@current_index}"
    set_form_row # 2009-01-17 12:44 
    @repaint_required = true
    #bounds_check
  end

end
