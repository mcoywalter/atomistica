!! ======================================================================
!! Atomistica - Interatomic potential library
!! https://github.com/pastewka/atomistica
!! Lars Pastewka, lars.pastewka@iwm.fraunhofer.de, and others.
!! See the AUTHORS file in the top-level Atomistica directory.
!!
!! Copyright (2005-2013) Fraunhofer IWM
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

  !>
  !! Compute energy, force, virial etc.
  !<
  subroutine COMPUTE_FUNC(this, p, nl, epot, f, wpot, epot_per_at, &
       epot_per_bond, f_per_bond, wpot_per_at, wpot_per_bond, ierror)
    implicit none

    type(BOP_TYPE),     intent(inout) :: this
    type(particles_t),  intent(inout) :: p
    type(neighbors_t),  intent(inout) :: nl
    real(DP),           intent(inout) :: epot
    real(DP),           intent(inout) :: f(3, p%maxnatloc)  !< forces
    real(DP),           intent(inout) :: wpot(3, 3)
    real(DP), optional, intent(inout) :: epot_per_at(p%maxnatloc)
    real(DP), optional, intent(inout) :: epot_per_bond(nl%neighbors_size)
    real(DP), optional, intent(inout) :: f_per_bond(3, nl%neighbors_size)
#ifdef LAMMPS
    real(DP), optional, intent(inout) :: wpot_per_at(6, p%maxnatloc)
    real(DP), optional, intent(inout) :: wpot_per_bond(6, nl%neighbors_size)
#else
    real(DP), optional, intent(inout) :: wpot_per_at(3, 3, p%maxnatloc)
    real(DP), optional, intent(inout) :: wpot_per_bond(3, 3, nl%neighbors_size)
#endif
    integer,  optional, intent(out)   :: ierror

    ! ---

    integer  :: i, el(p%maxnatloc)

    ! ---

    INIT_ERROR(ierror)

    call timer_start(BOP_NAME_STR // "_force")

    call update(nl, p, ierror)
    PASS_ERROR(ierror)

    ! Internal element numbers
    el = -1
    do i = 1, p%nat
       if (p%el2Z(p%el(i)) > 0) then
         el(i) = this%Z2db(p%el2Z(p%el(i)))
       endif
    enddo

#ifdef LAMMPS
    call BOP_KERNEL( &
         this, &
         p%maxnatloc, p%natloc, p%nat, p%r_non_cyc, &
         el, &
         nl%seed, nl%last, nl%neighbors, nl%neighbors_size, &
         epot, f, wpot, &
         epot_per_at, epot_per_bond, f_per_bond, wpot_per_at, wpot_per_bond, &
         ierror)
#else
    call BOP_KERNEL( &
         this, p%Abox, &
         p%maxnatloc, p%natloc, p%nat, p%r_non_cyc, &
         el, &
         nl%seed, nl%last, nl%neighbors, nl%neighbors_size, nl%dc, p%shear_dx, &
         epot, f, wpot, &
         epot_per_at, epot_per_bond, f_per_bond, wpot_per_at, wpot_per_bond, &
         ierror)
#endif
    PASS_ERROR(ierror)

    call timer_stop(BOP_NAME_STR // "_force")

  endsubroutine COMPUTE_FUNC