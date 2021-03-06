!! ======================================================================
!! Atomistica - Interatomic potential library and molecular dynamics code
!! https://github.com/Atomistica/atomistica
!!
!! Copyright (2005-2020) Lars Pastewka <lars.pastewka@imtek.uni-freiburg.de>
!! and others. See the AUTHORS file in the top-level Atomistica directory.
!!
!! This program is free software: you can redistribute it and/or modify
!! it under the terms of the GNU General Public License as published by
!! the Free Software Foundation, either version 2 of the License, or
!! (at your option) any later version.
!!
!! This program is distributed in the hope that it will be useful,
!! but WITHOUT ANY WARRANTY; without even the implied warranty of
!! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!! GNU General Public License for more details.
!!
!! You should have received a copy of the GNU General Public License
!! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!! ======================================================================

! @meta
!   shared
!   classtype:lj_cut_t classname:LJCut interface:potentials
!   features:mask,per_at
! @endmeta

!>
!! The 12-6 Lennard-Jones potential
!!
!! The 12-6 Lennard-Jones potential
!<

#include "macros.inc"
#include "filter.inc"

module lj_cut
  use libAtoms_module

  use ptrdict

  use logging
  use timer

  use neighbors
  use particles
  use filter

  implicit none

  private

  public :: lj_cut_t
  type lj_cut_t

     !
     ! Element on which to apply the force
     !

     character(MAX_EL_STR) :: element1 = "*"
     character(MAX_EL_STR) :: element2 = "*"
     integer               :: el1
     integer               :: el2

     !
     ! constants
     !
     
     real(DP)      :: epsilon = 1.0_DP
     real(DP)      :: sigma = 1.0_DP
     real(DP)      :: cutoff = 1.0_DP
     logical(BOOL) :: shift = .false.

     !
     ! derived parameters
     !

     real(DP) :: offset

  endtype lj_cut_t


  public :: init
  interface init
     module procedure lj_cut_init
  endinterface

  public :: del
  interface del
     module procedure lj_cut_del
  endinterface

  public :: bind_to
  interface bind_to
     module procedure lj_cut_bind_to
  endinterface

  public :: energy_and_forces
  interface energy_and_forces
     module procedure lj_cut_energy_and_forces
  endinterface

  public :: register
  interface register
     module procedure lj_cut_register
  endinterface

contains

  !>
  !! Constructor
  !!
  !! Constructor
  !<
  subroutine lj_cut_init(this)
    implicit none

    type(lj_cut_t), intent(inout)     :: this

    ! ---

  endsubroutine lj_cut_init


  !>
  !! Destructor
  !!
  !! Destructor
  !<
  subroutine lj_cut_del(this)
    implicit none

    type(lj_cut_t), intent(inout)  :: this

    ! ---

  endsubroutine lj_cut_del


  !>
  !! Initialization
  !!
  !! Initialization
  !<
  subroutine lj_cut_bind_to(this, p, nl, ierror)
    implicit none

    type(lj_cut_t),    intent(inout) :: this
    type(particles_t), intent(in)    :: p
    type(neighbors_t), intent(inout) :: nl
    integer, optional, intent(inout) :: ierror

    ! ---

    integer :: i, j

    ! ---

    this%el1 = filter_from_string(this%element1, p)
    this%el2 = filter_from_string(this%element2, p)

    call prlog("- lj_cut_bind_to -")
    call filter_prlog(this%el1, p, indent=5)
    call filter_prlog(this%el2, p, indent=5)
    call prlog("     epsilon  = "//this%epsilon)
    call prlog("     sigma    = "//this%sigma)
    call prlog("     cutoff   = "//this%cutoff)
    call prlog("     shift    = "//logical(this%shift))

    do i = 1, p%nel
       do j = 1, p%nel
          if (IS_EL2(this%el1, i) .and. IS_EL2(this%el2, j)) then
             call request_interaction_range(nl, this%cutoff, i, j)
          endif
       enddo
    enddo

    this%offset = 0.0_DP
    if (this%shift) then
       this%offset = 4*this%epsilon*((this%sigma/this%cutoff)**12 - &
            (this%sigma/this%cutoff)**6)
    endif

    call prlog("     * offset = "//this%offset)

    call prlog

  endsubroutine lj_cut_bind_to


  !>
  !! Compute the force
  !!
  !! Compute the force
  !<
  subroutine lj_cut_energy_and_forces(this, p, nl, epot, f, wpot, mask, &
       epot_per_at, wpot_per_at, ierror)
    implicit none

    type(lj_cut_t),     intent(inout) :: this
    type(particles_t),  intent(in)    :: p
    type(neighbors_t),  intent(inout) :: nl
    real(DP),           intent(inout) :: epot
    real(DP),           intent(inout) :: f(3, p%maxnatloc)  !< forces
    real(DP),           intent(inout) :: wpot(3, 3)
    integer,  optional, intent(in)    :: mask(p%maxnatloc)
    real(DP), optional, intent(inout) :: epot_per_at(p%maxnatloc)
#ifdef LAMMPS
    real(DP), optional, intent(inout) :: wpot_per_at(6, p%maxnatloc)
#else
    real(DP), optional, intent(inout) :: wpot_per_at(3, 3, p%maxnatloc)
#endif
    integer,  optional, intent(inout) :: ierror

    ! ---

    integer             :: i, j, weighti, weight
    integer(NEIGHPTR_T) :: jn
    real(DP)            :: dr(3), df(3), dw(3, 3)
    real(DP)            :: e, w(3, 3), cut_sq, abs_dr, for, en, fac12, fac6
    logical             :: maskj

    ! ---

    call timer_start("lj_cut_energy_and_forces")

    call update(nl, p, ierror)
    PASS_ERROR(ierror)

    e  = 0.0_DP
    w  = 0.0_DP

    cut_sq = this%cutoff**2

    !$omp  parallel default(none) &
    !$omp& firstprivate(cut_sq) &
    !$omp& private(dr, df, dw, abs_dr, for, en, fac12, fac6) &
    !$omp& private(i, j, weighti, weight, jn, maskj) &
    !$omp& shared(nl, f, p, mask) &
    !$omp& shared(epot_per_at, wpot_per_at, this) &
    !$omp& reduction(+:e) reduction(+:w)

    call tls_init(p%nat, sca=1, vec=1)

    !$omp do
    do i = 1, p%natloc
       weighti = 1
       if (present(mask)) then
          if (mask(i) == 0) then
             weighti = 0
          endif
       endif

       do jn = nl%seed(i), nl%last(i)
          j = GET_NEIGHBOR(nl, jn)

          if (i <= j) then
             maskj = .false.
             if (present(mask)) then
                if (mask(j) == 0) then
                   maskj = .true.
                endif
             endif
             if (i == j .or. j > p%natloc .or. maskj) then
                weight = weighti
             else
                weight = weighti + 1
             endif

             if ( weight > 0 .and. &
                  ( (IS_EL(this%el1, p, i) .and. IS_EL(this%el2, p, j)) .or. &
                    (IS_EL(this%el2, p, i) .and. IS_EL(this%el1, p, j)) ) ) then

                DIST_SQ(p, nl, i, jn, dr, abs_dr)

                if (abs_dr < cut_sq) then
                   abs_dr = sqrt(abs_dr)

                   fac12 = (this%sigma/abs_dr)**12
                   fac6  = (this%sigma/abs_dr)**6

                   en  = 0.5_DP*weight*(4*this%epsilon*(fac12-fac6)-this%offset)
                   for = 0.5_DP*weight*24*this%epsilon*(2*fac12-fac6)/abs_dr

                   df = for * dr/abs_dr

                   VEC3(tls_vec1, i) = VEC3(tls_vec1, i) + df
                   VEC3(tls_vec1, j) = VEC3(tls_vec1, j) - df

                   en = en/2
                   tls_sca1(i) = tls_sca1(i) + en
                   tls_sca1(j) = tls_sca1(j) + en

                   dw = -outer_product(dr, df)
                   w = w + dw
                   if (present(wpot_per_at)) then
                      dw = dw/2
                      SUM_VIRIAL(wpot_per_at, i, dw)
                      SUM_VIRIAL(wpot_per_at, j, dw)
                   endif

                endif
             endif
          endif
       enddo
    enddo

    e  = e + sum(tls_sca1(1:p%natloc))

    if (present(epot_per_at)) then
       call tls_reduce(p%nat, sca1=epot_per_at, vec1=f)
    else
       call tls_reduce(p%nat, vec1=f)
    endif

    !$omp end parallel

    epot  = epot + e
    wpot  = wpot + w

    call timer_stop("lj_cut_energy_and_forces")

  endsubroutine lj_cut_energy_and_forces


  subroutine lj_cut_register(this, cfg, m)
    use, intrinsic :: iso_c_binding

    implicit none

    type(lj_cut_t), target      :: this
    type(c_ptr),    intent(in)  :: cfg
    type(c_ptr),    intent(out) :: m

    ! ---

    m = ptrdict_register_section(cfg, CSTR("LJCut"), &
         CSTR("12-6 Lennard_Jones potential (with a hard cutoff)"))

    call ptrdict_register_string_property(m, c_locs(this%element1), &
         MAX_EL_STR, CSTR("el1"), CSTR("First element."))
    call ptrdict_register_string_property(m, c_locs(this%element2), &
         MAX_EL_STR, CSTR("el2"), CSTR("Second element."))

    call ptrdict_register_real_property(m, c_loc(this%epsilon), &
         CSTR("epsilon"), CSTR("Energy parameter."))
    call ptrdict_register_real_property(m, c_loc(this%sigma), &
         CSTR("sigma"), CSTR("Range parameter."))
    call ptrdict_register_real_property(m, c_loc(this%cutoff), CSTR("cutoff"), &
         CSTR("Cutoff length."))
    call ptrdict_register_boolean_property(m, c_loc(this%shift), &
         CSTR("shift"), CSTR("Shift potential to zero energy at cutoff."))

  endsubroutine lj_cut_register

endmodule lj_cut
