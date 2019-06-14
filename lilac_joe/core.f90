module lilac

  use ESMF
  use esmf_utils

  use lilac_utils , only create_fldlists, fldsMax


  implicit none

  character(*), parameter :: modname =  "(core)"
  integer, parameter :: LILAC_SUCCESS = ESMF_SUCCESS

  ! shared module level variables
  character(len=*)    :: atm_mesh_filepath
  type(LilacFields)   :: a2x_state
  type(LilacFields)   :: x2a_state

  !--------------------------------------------------------------------------
  ! Public interfaces
  !--------------------------------------------------------------------------
  public :: start
  public :: init
  public :: run
  public :: final

  private  :: atmos_register 
  private  :: land_register
  private  :: cpl_register

  type, public :: LilacType
     private

     type(ESMFInfoType) :: esmf_info

   contains
     procedure, public  :: init  => init
     procedure, public  :: run => run
     procedure, public  :: final => final

     ! register methods
     procedure, nopass, private  :: atmos_register  => atmos_register
     procedure, nopass, private  :: land_register => land_register
     procedure, nopass, private  :: cpl_register => cpl_register

     ! Init methods
     procedure, nopass, private  :: atmos_init  => atmos_init
     procedure, nopass, private  :: land_init  => land_init
     procedure, nopass, private  :: coupler_init  => coupler_init

     ! Run methods
     procedure, nopass, private  :: atmos_copy_atm_to_lilac => atmos_copy_atm_to_lilac
     procedure, nopass, private  :: atmos_copy_lilac_to_atm => atmos_copy_lilac_to_atm
     procedure, nopass, private  :: land_run => land_run
     procedure, nopass, private  :: coupler_run => coupler_run

     ! Final methods
     procedure, nopass, private  :: atmos_final => atmos_final
     procedure, nopass, private  :: land_final => land_final
     procedure, nopass, private  :: coupler_final => coupler_final

  end type LilacType

  type, public :: LilacFields
     private

     real, dimension(:, :), allocatable :: fields
     character(len=:), allocatable :: field_names(:)

   contains
     procedure, public :: init => init_lilac_state
     procedure, public :: get => get_lilac_field
  end type LilacFields

contains

  subroutine start(self, rc)
    implicit none
    class(LilacType), intent(inout)        :: self
    integer, intent(in)                    :: rc=ESMF_SUCCESS

    character(len=*), parameter :: subname=trim(modname)//':(init) '

    call ESMF_LogWrite(subname//"Starting lilac and setting up ESMF", ESMF_LOGMSG_INFO)

    ! Initialize ESMF structures
    call self%esmf_info%start(rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

  end subroutine start

  subroutine init(self, clock, x2a_state, a2x_state, rc)
    implicit none
    class(LilacType), intent(inout)  :: self
    type(ESMF_Clock)                 :: clock  ! Input synchronization clock
    type(LilacFields)                :: x2a_state
    type(LilacFields)                :: a2x_state
    integer, intent(in)              :: rc=ESMF_SUCCESS

    character(len=*), parameter :: subname=trim(modname)//':(init) '

    call ESMF_LogWrite(subname//"Initializing lilac", ESMF_LOGMSG_INFO)

    call self%esmf_info%start(atmos_register, land_register, cpl_register, rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

  end subroutine init

  subroutine run(self, clock, x2a_state, a2x_state, rc)
    implicit none
    class(LilacType), intent(inout)  :: self
    type(ESMF_Clock)                 :: clock  ! Input synchronization clock
    type(LilacFields)                :: x2a_state
    type(LilacFields)                :: a2x_state
    integer, intent(in)              :: rc=ESMF_SUCCESS

    character(len=*), parameter :: subname=trim(modname)//':(run) '

    call ESMF_LogWrite(subname//"Running lilac", ESMF_LOGMSG_INFO)

    ! save states to module level variable here

    call self%esmf_info%run(rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

  end subroutine run

  subroutine final(self, rc)
    implicit none
    class(LilacType), intent(inout)  :: self
    integer, intent(in)              :: rc=ESMF_SUCCESS

    character(len=*), parameter :: subname=trim(modname)//':(final) '

    call ESMF_LogWrite(subname//"Finalizing lilac", ESMF_LOGMSG_INFO)

    call self%esmf_info%final(rc)

  end subroutine final

  subroutine atmos_register(comp, rc)
    type(ESMF_GridComp)   :: comp   ! must not be optional
    integer, intent(in)   :: rc=ESMF_SUCCESS

    character(len=*), parameter :: subname=trim(modname)//':(atmos_register) '

    ! Set the entry points for standard ESMF Component methods
    call ESMF_GridCompSetEntryPoint(comp, ESMF_METHOD_INITIALIZE, userRoutine=atmos_init, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    call ESMF_GridCompSetEntryPoint(comp, ESMF_METHOD_RUN, userRoutine=atmos_copy_atm_to_lilac, phase=1, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    call ESMF_GridCompSetEntryPoint(comp, ESMF_METHOD_RUN, userRoutine=atmos_copy_lilac_to_atm, phase=2, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    call ESMF_GridCompSetEntryPoint(comp, ESMF_METHOD_FINALIZE, userRoutine=atmos_final, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    rc = ESMF_SUCCESS

  end subroutine atmos_register

  subroutine land_register(comp, rc)
    type(ESMF_GridComp)   :: comp   ! must not be optional
    integer, intent(out)  :: rc     ! must not be optional
    character(len=*), parameter :: subname=trim(modname)//':(lnd_register) '

    ! land_* comes from ctsm esmf cap

    ! Set the entry points for standard ESMF Component methods
    call ESMF_GridCompSetEntryPoint(comp, ESMF_METHOD_INITIALIZE, userRoutine=land_init, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    call ESMF_GridCompSetEntryPoint(comp, ESMF_METHOD_RUN, userRoutine=land_run, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    call ESMF_GridCompSetEntryPoint(comp, ESMF_METHOD_FINALIZE, userRoutine=land_final, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    rc = ESMF_SUCCESS

  end subroutine land_register

  subroutine cpl_register(comp, rc)
    type(ESMF_CplComp)   :: comp   ! must not be optional
    integer, intent(out)  :: rc     ! must not be optional
    character(len=*), parameter :: subname=trim(modname)//':(cpl_register) '

    rc = ESMF_FAILURE

    ! Register the callback routines.
    call ESMF_CplCompSetEntryPoint(comp, ESMF_METHOD_INITIALIZE, userRoutine=coupler_init, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    call ESMF_CplCompSetEntryPoint(comp, ESMF_METHOD_RUN, userRoutine=coupler_run, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    call ESMF_CplCompSetEntryPoint(comp, ESMF_METHOD_FINALIZE, userRoutine=coupler_final, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    call ESMF_LogWrite(subname//"CouplerMod: Registered Initialize, Run, and Finalize routines", ESMF_LOGMSG_INFO)

    rc = ESMF_SUCCESS

  end subroutine cpl_register

  subroutine atmos_init(comp, importState, exportState, clock, rc)
    type(ESMF_GridComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    type (fld_list_type)   :: fldsToCpl(fldsMax)
    type (fld_list_type)   :: fldsFrCpl(fldsMax)
    integer                :: fldsToCpl_num
    integer                :: fldsFrCpl_num

    character(len=*), parameter :: subname=trim(modname)//':(atmos_init) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    ! read in the mesh
    if (masterproc) then
       write(iulog,*)'mesh file for domain is ',trim(atm_mesh_filepath)
    end if
    ! move to lilac dummy atmosphere init?
    EMesh = ESMF_MeshCreate(filename=trim(atm_mesh_filepath), fileformat=ESMF_FILEFORMAT_ESMFMESH, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    ! create field lists
    call create_fldlists(fldsFrCpl, fldsToCpl, fldsToCpl_num, fldsFrCpl_num)

    ! Create States
    x2a_state = ESMF_StateCreate(name="x2a_state", stateintent=ESMF_STATEINTENT_IMPORT, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out
    a2x_state = ESMF_StateCreate(name="x2a_state",  stateintent=ESMF_STATEINTENT_EXPORT, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    ! Coupler to Atmosphere Fields
    FBout = ESMF_FieldBundleCreate(name="x2a_fields", rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    ! Create individual states and add to field bundle
    do n = 1,fldsFrCpl_num
       ! create field
       field = ESMF_FieldCreate(lmesh, ESMF_TYPEKIND_R8, meshloc=meshloc, name=trim(fldsFrCpl(n)%stdname), rc=rc)
       if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out
       ! add field to field bundle
       call ESMF_FieldBundleAdd(FBout, (/field/), rc=rc)
       if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out
    enddo

    ! Add FB to state
    call ESMF_StateAdd(x2a_state, (/FBout/), rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    ! Atmosphere to Coupler Fields
    FBout = ESMF_FieldBundleCreate(name="a2x_fields", rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

    ! Create individual states and add to field bundle
    do n = 1,fldsToCpl_num
       ! create field
       field = ESMF_FieldCreate(lmesh, ESMF_TYPEKIND_R8, meshloc=meshloc, name=trim(fldsToCpl(n)%stdname), rc=rc)
       if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out
       ! initialize with default value
       call ESMF_FieldGet(lfield, farrayPtr=fldptr, rc=rc)
       if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out
       ldptr = fldsToCpl(n)%default_value

       ! add field to field bundle
       call ESMF_FieldBundleAdd(FBout, (/field/), rc=rc)
       if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out
    enddo

    ! Add FB to state
    call ESMF_StateAdd(a2x_state, (/FBout/), rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, line=__LINE__, file=__FILE__)) return  ! bail out

  end subroutine atmos_init

  subroutine land_init(comp, importState, exportState, clock, rc)
    type(ESMF_GridComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(land_init) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"land_init has not been implemented yet", ESMF_LOGMSG_INFO)

  end subroutine land_init

  subroutine coupler_init(comp, importState, exportState, clock, rc)
    type(ESMF_CplComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(coupler_init) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"coupler_init has not been implemented yet", ESMF_LOGMSG_INFO)

  end subroutine coupler_init

  subroutine atmos_copy_atm_to_lilac(comp, importState, exportState, clock, rc)
    type(ESMF_GridComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(atmos_copy_atm_to_lilac) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"atmos_copy_atm_to_lilac has not been implemented yet", ESMF_LOGMSG_INFO)

    ! loop over fields, copying pointer from import to export state

  end subroutine atmos_copy_atm_to_lilac

  subroutine atmos_copy_lilac_to_atm(comp, importState, exportState, clock, rc)
    type(ESMF_GridComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(atmos_copy_lilac_to_atm) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"atmos_copy_lilac_to_atm has not been implemented yet", ESMF_LOGMSG_INFO)

  end subroutine atmos_copy_lilac_to_atm

  subroutine land_run(comp, importState, exportState, clock, rc)
    type(ESMF_GridComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(land_run) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"land_run has not been implemented yet", ESMF_LOGMSG_INFO)

  end subroutine land_run

  subroutine coupler_run(comp, importState, exportState, clock, rc)
    type(ESMF_CplComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(coupler_run) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"coupler_run has not been implemented yet", ESMF_LOGMSG_INFO)

  end subroutine coupler_run

  subroutine atmos_final(comp, importState, exportState, clock, rc)
    type(ESMF_GridComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(atmos_final) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"atmos_final has not been implemented yet", ESMF_LOGMSG_INFO)

  end subroutine atmos_final

  subroutine land_final(comp, importState, exportState, clock, rc)
    type(ESMF_GridComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(land_final) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"land_final has not been implemented yet", ESMF_LOGMSG_INFO)

  end subroutine land_final

  subroutine coupler_final(comp, importState, exportState, clock, rc)
    type(ESMF_CplComp)  :: comp
    type(ESMF_State)     :: importState, exportState
    type(ESMF_Clock)     :: clock
    integer, intent(out) :: rc

    character(len=*), parameter :: subname=trim(modname)//':(coupler_final) '

    ! Initialize return code
    rc = ESMF_SUCCESS

    call ESMF_LogWrite(subname//"coupler_final has not been implemented yet", ESMF_LOGMSG_INFO)

  end subroutine coupler_final

  subroutine init_lilac_state(self, field_list, nlocal)
    implicit none
    class(LilacFields), intent(inout)   :: self
    type(fld_list_type), intent(inout) :: field_list(:)
    integer, intent(in)                :: nlocal

    integer :: nfields, i

    nfields = size(field_list)

    allocate(character(MAXCHAR) :: self%field_names(nfields))
    allocate(self%fields(nfields, nlocal))

    do i = 1, nfields
       self%field_names(i) = field_list(i)%stdname
       self%fields(i) = field_list(i)%default_value
    enddo

  end subroutine init_lilac_state


  function get_lilac_field(self, field_name) result(array_ptr)
    implicit none
    class(LilacFields) :: self
    character(len=*)   :: field_name
    pointer :: array_ptr

    integer :: i

    nfields = size(self%field_names)

    do i = 1, nfields
       if (field_name .eq. (self%field_names(i))) then
          ptr => self%fields(i, :)
          return
       endif
    enddo

    ! Raise error here
    call ESMF_LogWrite("KeyError: Did not find variable in LilacFields object" // field_name, ESMF_LOGMSG_INFO)

  end function get_lilac_field

end module lilac