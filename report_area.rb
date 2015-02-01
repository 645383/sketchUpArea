require 'sketchup.rb'

module ReportArea

  def self.register_plugin_for_LibFredo6
    {
        :name => "ReportArea",
        :author => "Fredo6",
        :version => "1.1a",
        :date => "10 Sep 11",
        :description => @tooltip,
        :link_info => "http://forums.sketchucation.com/viewtopic.php?f=323&t=40025#p354050"
    }
  end

  @@report_type = nil
  @@units = nil

  def self.install_plugin
    @hsh_texts = {}

    @menutitle = "Report Area"
    @tooltip = "Report Area for the selection or the whole model, with choice of units and CSV export"
    @msg_processing = "PROCESSING"
    @msg_done = "DONE"
    @msg_noface = "NO face in the selection"
    @msg_total_area = "TOTAL AREA"
    @msg_open_file1 = "CSV File generated"
    @msg_open_file2 = "Do you want to open it?"
    @hsh_texts[:group] = "GROUP"
    @hsh_texts[:comp_inst] = "COMPONENT INSTANCE"
    @msg_name = "Name"
    @msg_area = "Area"
    @msg_type_report = "Select the Type of Report"
    @msg_units = "Units"
    @report_console = "Ruby Console"
    @report_CSV = "CSV file"
    @title = "Generate a report on Areas"


    #Main menu
    sumenu = UI.menu "Plugins"
    sumenu.add_item(@menutitle) { execute }

    #Contextual menu
    UI.add_context_menu_handler do |menu|
      ss = Sketchup.active_model.selection
      if valid_selection?(ss)
        menu.add_item(@menutitle) { execute ss }
      end
    end
  end

#Check if the component is a DXF imported component
  def self.valid_selection?(selection)
    selection.each do |e|
      return true if e.instance_of?(Sketchup::Face) || e.instance_of?(Sketchup::Group) ||
          e.instance_of?(Sketchup::ComponentInstance)
    end
    false
  end

#Initialize and execute the top function
  def self.execute(selection=nil)
    #Initialization
    model = Sketchup.active_model
    selection = model.selection unless selection
    entities = (selection == nil || selection.empty?) ? model.active_entities : selection
    t = Geom::Transformation.new
    init_info

    #Exploring the selection
    Sketchup.set_status_text @msg_processing, SB_VCB_LABEL

    explore_selection entities, nil, t

    Sketchup.set_status_text @msg_done, SB_VCB_LABEL
    Sketchup.set_status_text "#{Sketchup.format_area @total_area}", SB_VCB_VALUE
    Sketchup.set_status_text @msg_total_area + " #{Sketchup.format_area @total_area}"

    #NO face in the selection
    # if @hsh_info[:mat].length == 0
    #   UI.messagebox @msg_noface
    #   return
    # end

    #Asking for Action
    return unless ask_for_report
    @factor_unit = factor_convertion @@units

    #Console Report
    if @@report_type == @report_console
      generate_report_console
      return
    end

    #Generating the report in CSV format
    path = ask_path model
    return unless path
    generate_report_csv path

    #Opening the file
    text = @msg_open_file1 + "\n\n #{path}"
    text += "\n\n" + @msg_open_file2
    status = UI.messagebox(text, MB_YESNO)
    UI.openURL path if status == 6
  end

#Recursive exploration of the selection	
  def self.explore_selection(entities, comp, t)
    entities.each do |e|
      if e.instance_of?(Sketchup::Face)
        report_on_face e, comp, t
      elsif e.instance_of?(Sketchup::Group)
        explore_selection e.entities, e, t * e.transformation
      elsif e.instance_of?(Sketchup::ComponentInstance)
        explore_selection e.definition.entities, e, t * e.transformation
      end
    end
  end

#----------------------------------------------------------------------------------------
# UI Dialogs
#----------------------------------------------------------------------------------------

#Dialog box to ask	
  def self.ask_for_report
    combo = [@combo_reports, @combo_units]
    unless @@report_type
      @@report_type = @report_console
    end
    unless @@units
      @@units = @lst_units[0]
    end
    values = [@@report_type, @@units]

    results = UI.inputbox @dlg_prompts, values, combo, @title
    return false unless results
    @@report_type, @@units = results
    true
  end

#Ask for the path of the file	
  def self.ask_path(model)
    path = model.path
    curdate = Time.now.strftime "%d%b%y-%Hh%M"
    if path.empty?
      dir = ""
      name = "ReportArea_untitled_#{curdate}.csv"
    else
      dir = File.dirname(path)
      name = File.basename(path, ".skp") + "_ReportArea_#{curdate}.csv"
    end
    UI.savepanel @menutitle, dir, name
  end

  def self.format_area(area)
    "#{area * @factor_unit} #{@@units}"
  end

#----------------------------------------------------------------------------------------
# Storing the information
#----------------------------------------------------------------------------------------

  PseudoObj = Struct.new :su_obj, :type, :name, :area, :pdef, :nb_faces, :faces


#Initialize the information structures
  def self.init_info
    @hsh_info = {}
    @hsh_numdef = Hash.new 0
    @total_area = 0
    @lst_keys = [:group, :comp_inst]
    @lst_keys.each { |key| @hsh_info[key] = {} }
    @lst_units = ["sq. feet"]
    @dlg_prompts = [@msg_type_report, @msg_units]
    @combo_units = @lst_units.join "|"
    @combo_reports = [@report_console, @report_CSV].join "|"
  end

#Reporting on face
  def self.report_on_face(face, comp, t)
    #Calculating the area
    # loops = face.loops.collect { |loop| loop.vertices.collect { |v| t * v.position } }
    # pt1 = face.outer_loop.vertices[0].position
    # normal = (t * pt1).vector_to(t * pt1.offset(face.normal, 1))
    # area = pseudo_face_area loops, normal
    area = face.area

    #Storing the information
    @total_area += area
    store_info :group, comp, area
    # store_info :back_mat, face.back_material, area
    # store_info :comp_inst, comp, area
  end

#Create an information entry in the given hash table	
  def self.store_info(type, obj, area)
    #Hahs array to store the info
    if obj.class == Sketchup::Group
      type = :group
    elsif obj.class == Sketchup::ComponentInstance
      type = :comp_inst
    end

    hsh = @hsh_info[type]
    return unless hsh

    #Storing the info
    id = (obj) ? obj.entityID : 0
    pobj = hsh[id]
    pobj = hsh[id] = PseudoObj.new unless pobj
    pobj.su_obj = obj
    pobj.name = (obj) ? obj.name : ""
    pobj.area = 0 unless pobj.area
    pobj.area += area
    pobj.nb_faces = 0 unless pobj.nb_faces
    pobj.nb_faces += 1

    #Special treatment depending on object
    if obj.class == Sketchup::ComponentInstance
      cdef = obj.definition
      pobj.pdef = store_info :comp_def, cdef, area
      name = (obj.name.empty?) ? "##{cdef.instances.rindex(obj)+1}" : obj.name
      pobj.name = obj.definition.name + ":" + name
    elsif obj.class == Sketchup::Group
      name = (obj.name.empty?) ? "##{@hsh_info[:group].length}" : obj.name

      pobj.name = @hsh_texts[:group] + ":" + name

      pobj.faces = obj.entities.map { |entity|
        if entity.class == Sketchup::Face
          horizon = []
          entity.vertices.map { |vertex|
            vertex.position.to_a
          }.flatten.each_with_index { |point, i| horizon << point if (i+1)%3 == 0 }

          if horizon.uniq.count == 1
            face_name = "#{name}_floor"
          else
            face_name = "#{name}_window"
          end
          [face_name, entity.area]
        end
      }.compact

    elsif obj == nil
      if type == :mat || type == :back_mat
        pobj.name = "--default--"
      else
        pobj.name = "--Active_model--"
      end
    end
    pobj
  end

#----------------------------------------------------------------------------------------
# Generating the Report
#----------------------------------------------------------------------------------------

  def self.generate_report_console
    @lst_keys.each do |key|
      hsh = @hsh_info[key]
      next unless hsh.length > 0
      puts "\n#{@hsh_texts[key]}"
      lst = hsh.values.sort { |a, b| a.name <=> b.name }
      lst.each do |pobj|
        puts "   #{pobj.name} --> #{format_area pobj.area}"
      end
      puts "\n#{@msg_total_area} --> #{format_area @total_area}"
    end
  end

#CSV Format	
  def self.generate_report_csv(path)
    sepa = ","
    headers = [@msg_name, "#{@msg_area} (#{@@units})"]
    File.open(path, "w") do |f|
      f.puts headers.join(sepa)
      f.puts ""
      @lst_keys.each do |key|
        hsh = @hsh_info[key]
        next unless hsh.length > 0
        f.puts "#{@hsh_texts[key]}"
        lst = hsh.values.sort { |a, b| a.name <=> b.name }
        lst.each do |pobj|
          f.puts [pobj.name, "#{pobj.area * @factor_unit}", @@units].join(sepa)
          pobj.faces.each { |face|
            f.puts [face[0], "#{(face[1] * @factor_unit)}", @@units].join(sepa)
          }
        end
      end
      f.puts ""
      f.puts [@msg_total_area, "#{@total_area * @factor_unit}", @@units]
    end
  end

#----------------------------------------------------------------------------------------
# Calculation of area
#----------------------------------------------------------------------------------------

#Area of a planar polygon (points given in 2D)
  def self.polygon_area(lpt_2d)
    area = 0.0
    for i in 0..lpt_2d.length-2
      pt1 = lpt_2d[i]
      pt2 = lpt_2d[i+1]
      area += pt1.x * pt2.y - pt2.x * pt1.y
    end
    0.5 * area.abs
  end

#Calculate the area of a face given by its loops and normal
  def self.pseudo_face_area(loops, normal)
    #Finding the plane
    axes = normal.axes
    tr_axe = Geom::Transformation.axes loops[0][0], *axes
    tr_axe_inv = tr_axe.inverse

    #Area for outer_loop
    lpt_2d = loops[0].collect { |pt| tr_axe_inv * pt }
    lpt_2d.push lpt_2d[0]
    area = polygon_area lpt_2d

    #Area for inner loops
    if loops.length > 1
      loops[1..-1].each do |loop|
        lpt_2d = loop.collect { |pt| tr_axe_inv * pt }
        lpt_2d.push lpt_2d[0]
        area -= polygon_area lpt_2d
      end
    end
    area
  end

#Compute the unit conversion factor
  def self.factor_convertion(sunit)
    case sunit
      when /inch/, /feet/, /km/, /mm/, /cm/, /mile/, /yard/, /m/
        f = eval "1.0.#{$&}"
      else
        f = 1.0
    end
    1.0 / f / f
  end

#----------------------------------------------------------------------------------------
# Menu and load for  Alternate Directory (called once)
#----------------------------------------------------------------------------------------

  unless $ReportArea____loaded
    self.install_plugin
    $ReportArea____loaded = true
  end

end #module ReportArea
