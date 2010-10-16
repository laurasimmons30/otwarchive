class PseudsController < ApplicationController

  before_filter :load_user
  before_filter :check_ownership, :only => [:create, :edit, :destroy, :new, :update]
  before_filter :check_user_status, :only => [:new, :create, :edit, :update]

  def load_user
    @user = User.find_by_login(params[:user_id])
    @check_ownership_of = @user
  end

  # GET /pseuds
  # GET /pseuds.xml
  def index
    if @user
      @pseuds = @user.pseuds.find(:all)
      @rec_counts = Pseud.rec_counts_for_pseuds(@pseuds)
      @work_counts = Pseud.work_counts_for_pseuds(@pseuds)      
    else
      redirect_to people_path
    end
  end

  # GET /users/:user_id/pseuds/:id
  # very similar to show under users - if you change something here, you'll probably need to change it there too
  def show
    if @user.blank?
      flash[:error] = ts("Sorry, could not find this user.")
      redirect_to people_path and return
    end
    @author = @user.pseuds.find_by_name(params[:id])
    unless @author
      flash[:error] = ts("Sorry, could not find this pseud.")
      redirect_to people_path and return
    end
    if current_user.nil?
      visible_works = @author.works.visible_to_all
      visible_series = @author.series.visible_to_all
      visible_bookmarks = @author.bookmarks.visible_to_all
    else
      visible_works = @author.works.visible_to_registered_user
      visible_series = @author.series.visible_to_registered_user
      visible_bookmarks = @author.bookmarks.visible_to_registered_user
    end
    @fandoms = @author.direct_filters.with_type("Fandom").by_name.uniq
    @works = visible_works.order("revised_at DESC").limit(ArchiveConfig.NUMBER_OF_ITEMS_VISIBLE_IN_DASHBOARD)
    @series = visible_series.order("updated_at DESC").limit(ArchiveConfig.NUMBER_OF_ITEMS_VISIBLE_IN_DASHBOARD)
    @bookmarks = visible_bookmarks.order("updated_at DESC").limit(ArchiveConfig.NUMBER_OF_ITEMS_VISIBLE_IN_DASHBOARD)
  end

  # For use with work/chapter forms
  def choose_coauthors
    byline = params[:search].strip
    if byline.include? "["
      split = byline.split('[', 2)
      pseud_name = split.first.strip
      user_login = split.last.chop
      @pseuds = where('LOWER(users.login) LIKE ? AND LOWER(name) LIKE ?','%' + user_login + '%',  '%' + pseud_name + '%')
    else
      @pseuds = where('LOWER(name) LIKE ?', '%' + byline + '%')
    end
    # UGH MAGIC NUMBER WHY 10
    @pseuds = @pseuds.includes(:user).limit(10)
    respond_to do |format|
      format.html
      format.js
    end
  end

  # GET /pseuds/new
  # GET /pseuds/new.xml
  def new
    @pseud = @user.pseuds.build
  end

  # GET /pseuds/1/edit
  def edit
    @pseud = @user.pseuds.find_by_name(params[:id])
  end

  # POST /pseuds
  # POST /pseuds.xml
  def create
    @pseud = Pseud.new(params[:pseud])
    unless @user.has_pseud?(@pseud.name)
      @user.pseuds << @pseud
      default = @user.default_pseud
      if @pseud.save
        flash[:notice] = t('successfully_created', :default => 'Pseud was successfully created.')
       if @pseud.is_default
          # if setting this one as default, unset the attribute of the current default pseud
          default.update_attribute(:is_default, false)
        end
        redirect_to([@user, @pseud])
      else
        render :action => "new"
      end
    else
      # user tried to add pseud he already has
      flash[:error] = t('duplicate_pseud', :default => 'You already have a pseud with that name.')
     @pseud.name = '' if @user.default_pseud.name == @pseud.name
      render :action => "new"
    end
  end

  # PUT /pseuds/1
  # PUT /pseuds/1.xml
  def update
    @pseud = @user.pseuds.find_by_name(params[:id])
    default = @user.default_pseud
    if @pseud.update_attributes(params[:pseud])
      # if setting this one as default, unset the attribute of the current default pseud
      if @pseud.is_default and not(default == @pseud)
        # if setting this one as default, unset the attribute of the current active pseud
        default.update_attribute(:is_default, false)
      end
      flash[:notice] = t('successfully_updated', :default => 'Pseud was successfully updated.')
     redirect_to([@user, @pseud])
    else
      render :action => "edit"
    end
  end

  # DELETE /pseuds/1
  # DELETE /pseuds/1.xml
  def destroy
    @hide_dashboard = true
    @pseud = @user.pseuds.find_by_name(params[:id])
    if @pseud.is_default
      flash[:error] = t('delete_default', :default => "You cannot delete your default pseudonym, sorry!")
   elsif @pseud.name == @user.login
      flash[:error] = t('delete_user_name', :default => "You cannot delete the pseud matching your user name, sorry!")
   elsif params[:bookmarks_action] == 'transfer_bookmarks'
     @pseud.change_bookmarks_ownership
     @pseud.replace_me_with_default
     flash[:notice] = t('successfully_deleted', :default => "The pseud was successfully deleted.")
   elsif params[:bookmarks_action] == 'delete_bookmarks' || @pseud.bookmarks.empty?
     @pseud.replace_me_with_default
     flash[:notice] = t('successfully_deleted', :default => "The pseud was successfully deleted.")
   else
      render 'delete_preview' and return  
   end

    redirect_to(user_pseuds_url(@user))
  end
end
