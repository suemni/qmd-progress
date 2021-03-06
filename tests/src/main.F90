
!> Applies a series of tests.
!! The name of the test is pased by an argument.
!! To use this program run: ./main test_name
!!
program main

  use bml
  use hamiltonian_mod
  use accuracy_mod
  use test_prg_subgraphloop_mod

  !progress lib modes
  use prg_progress_mod
  use prg_sp2_mod
  use prg_densitymatrix_mod
  use prg_nonortho_mod
  use prg_genz_mod
  use prg_graph_mod
  use prg_timer_mod

  !LATTE lib modes
  use prg_ptable_mod
  use prg_system_mod
  use tbparams_latte_mod
  use huckel_latte_mod

  implicit none

  integer :: norb, mdim, verbose
  type(bml_matrix_t) :: ham_bml
  type(bml_matrix_t) :: rho_bml
  type(bml_matrix_t) :: rho_ortho_bml
  type(bml_matrix_t) :: zmat_bml
  type(bml_matrix_t) :: nonortho_ham_bml
  type(bml_matrix_t) :: over_bml
  type(bml_matrix_t) :: aux_bml
  type(graph_partitioning_t) :: gp
  type(system_type) :: mol
  character(20) :: bml_type
  character(20) :: sp2conv_sue
  character(50) :: test
  character(20) :: dummy(10)
  real(dp) :: threshold, gthreshold, idempotency
  real(dp) :: bndfil, mu
  real(dp), allocatable :: ham(:,:), zmat(:,:)
  real(dp), allocatable :: nonortho_ham(:,:)
  real(dp), allocatable :: over(:,:)
  real(dp), allocatable :: rho_ortho(:,:)
  real(dp), allocatable :: rho(:,:)
  real(dp) :: sp2tol, idempotency_tol, ortho_error
  real(dp) :: error_calc, error_tol, errlimit
  real(dp) :: ortho_error_tol
  real(dp), allocatable :: gbnd(:)
  integer :: minsp2iter, icount, nodesPerPart
  integer :: maxsp2iter
  integer, allocatable :: pp(:)
  real(dp), allocatable :: vv(:)
  character(10) :: sp2conv
  type(tbparams_type) :: tbparams
  character(3), allocatable :: intKind(:)
  character(2), allocatable :: TypeA(:,:),TypeB(:,:)
  real(dp), allocatable :: onsitesH(:,:)
  real(dp), allocatable :: onsitesS(:,:)
  type(intpairs_type), allocatable :: intPairsH(:,:)
  type(intpairs_type), allocatable :: intPairsS(:,:)

  call getarg(1, test)
  write(*,*)"Performing test", test

  !Some parameters that can be changed depending on the test.
  bml_type = "dense"
  threshold = 1.0d-9
  mdim = -1
  verbose = 1
  minsp2iter = 25
  maxsp2iter = 100
  sp2tol = 1.0d-10
  sp2conv = "Rel"
  idempotency_tol = 1.0d-8
  !-----------------------------------------------------------

  !Initialize progress
  call prg_progress_init()

  !The following Hamiltonian belongs to a water box structure
  !which was precalculated with dftb+
  call h_read(ham,nOrb)
  bndfil = 0.666666666666666666_dp !Filing factor for water box systems

  !Convert the Hamiltonian to bml
  call bml_convert_from_dense(bml_type,ham,ham_bml,threshold,norb)

  !Allocate the density matrix
  call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)

  select case(test)

  case("prg_density") !Diagonalize H and build \rho

    write(*,*) "Testing the construction of the density matrix from density_mod"
    call prg_build_density_T0(ham_bml, rho_bml, threshold, bndfil)
    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    write(*,*)"Idempotency for prg_build_density_T0",idempotency
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

  case("prg_density_T") !Diagonalize H and build \rho with electronic temperature KbT

    write(*,*) "Testing the construction of the density at KbT > 0 matrix from density_mod"
    call prg_build_density_T(ham_bml, rho_bml, threshold, bndfil, 0.01_dp, mu)
    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    write(*,*)"Idempotency for prg_build_density_T0",idempotency
    write(*,*)"Fermi level:",mu
    if(idempotency.gt.1.0D-5)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

  case("prg_density_T_Fermi") !Diagonalize H and build \rho with electronic temperature KbT and with chemical potential mu

    write(*,*) "Testing the construction of the density matrix at KbT > 0 and at mu = Ef from density_mod"
    call prg_build_density_T_Fermi(ham_bml, rho_bml, threshold,0.01_dp, -0.10682896819759_dp, 1)
    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    write(*,*)"Idempotency for prg_build_density_T0",idempotency
    write(*,*)"Fermi level:",mu
    if(idempotency.gt.1.0D-5)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

  case("prg_sp2_basic") !Sp2 original version

    call prg_timer_start(loop_timer)

    call prg_timer_start(sp2_timer)
    call prg_sp2_basic(ham_bml,rho_bml,threshold,bndfil,minsp2iter,maxsp2iter &
      ,sp2conv,sp2tol,verbose)
    call prg_timer_stop(sp2_timer)
    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg1_dense") !Sp2 algorithm 1

    call prg_timer_start(loop_timer)

    bml_type = "dense"
    call bml_convert_from_dense(bml_type,ham,ham_bml,threshold,norb)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg1(ham_bml,rho_bml,threshold,bndfil,minsp2iter,maxsp2iter &
      ,sp2conv,sp2tol)
    call prg_timer_stop(sp2_timer)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg2_dense") !Sp2 algorithm 2

    call prg_timer_start(loop_timer)

    bml_type = "dense"
    call bml_convert_from_dense(bml_type,ham,ham_bml,threshold,norb)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2(ham_bml,rho_bml,threshold,bndfil,minsp2iter,maxsp2iter &
      ,sp2conv,sp2tol)
    call prg_timer_stop(sp2_timer)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg1_ellpack") !Sp2 algorithm 1

    call prg_timer_start(loop_timer)

    idempotency_tol = 1d-6
    bml_type = "ellpack"
    bndfil = 0.5_dp
    norb = 6144
    mdim = 600
    threshold = 1.0d-9
    sp2tol = 1.0d-10

    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,rho_bml)
    call bml_read_matrix(ham_bml, "poly.512.mtx")

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg1(ham_bml,rho_bml,threshold,bndfil,minsp2iter,maxsp2iter &
      ,sp2conv,sp2tol)
    call prg_timer_stop(sp2_timer)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg2_ellpack") !Sp2 algorithm 2 ellpack version

    call prg_timer_start(loop_timer)

    idempotency_tol = 1d-6
    bml_type = "ellpack"
    bndfil = 0.5_dp
    norb = 6144
    mdim = 600
    threshold = 1.0d-9
    sp2tol = 1.0d-10

    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,rho_bml)
    call bml_read_matrix(ham_bml, "poly.512.mtx")

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2(ham_bml,rho_bml,threshold,bndfil,minsp2iter,maxsp2iter &
      ,sp2conv,sp2tol)
    call prg_timer_stop(sp2_timer)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg2_ellpack_poly") !Sp2 algorithm 2 ellpack version

    call prg_timer_start(loop_timer)

    idempotency_tol = 1.0d-2
    bml_type = "ellpack"
    bndfil = 0.5_dp
    norb = 6144
    mdim = 288
    threshold = 1.0d-5
    sp2tol = 1.0d-10

    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,rho_bml)
    call bml_read_matrix(ham_bml, "poly.512.mtx")

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2(ham_bml,rho_bml,threshold,bndfil,minsp2iter,maxsp2iter &
      ,sp2conv,sp2tol)
    call prg_timer_stop(sp2_timer)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml, threshold, idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg1_seq_dense") !Sp2 algorithm 1 sequence version

    call prg_timer_start(loop_timer)

    bml_type = "dense"
    call bml_convert_from_dense(bml_type,ham,ham_bml,threshold,norb)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)

    allocate(pp(100),vv(100))
    icount = 0

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg1_genseq(ham_bml, rho_bml, threshold, bndfil, &
                          minsp2iter, maxsp2iter, sp2conv, sp2tol, &
                          pp, icount, vv)

    call prg_sp2_alg1_seq(ham_bml, rho_bml, threshold, pp, icount, vv)
    call prg_timer_stop(sp2_timer)

    deallocate(pp, vv)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg2_seq_dense") !Sp2 algorithm 2 sequence version

    call prg_timer_start(loop_timer)

    bml_type = "dense"
    call bml_convert_from_dense(bml_type,ham,ham_bml,threshold,norb)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)

    allocate(pp(100),vv(100))
    icount = 0

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2_genseq(ham_bml, rho_bml, threshold, bndfil, &
                          minsp2iter, maxsp2iter, sp2conv, sp2tol, &
                          pp, icount, vv)

    call prg_sp2_alg2_seq(ham_bml, rho_bml, threshold, pp, icount, vv)
    call prg_timer_stop(sp2_timer)

    deallocate(pp, vv)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg1_seq_ellpack") !Sp2 algorithm 1 sequence version

    call prg_timer_start(loop_timer)

    idempotency_tol = 1d-6
    bml_type = "ellpack"
    bndfil = 0.5_dp
    norb = 6144
    mdim = 600
    threshold = 1.0d-9
    sp2tol = 1.0d-10

    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,rho_bml)
    call bml_read_matrix(ham_bml, "poly.512.mtx")

    allocate(pp(100),vv(100))
    icount = 0

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg1_genseq(ham_bml, rho_bml, threshold, bndfil, &
                          minsp2iter, maxsp2iter, sp2conv, sp2tol, &
                          pp, icount, vv)

    call prg_sp2_alg1_seq(ham_bml, rho_bml, threshold, pp, icount, vv)
    call prg_timer_stop(sp2_timer)

    deallocate(pp, vv)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg2_seq_ellpack") !Sp2 algorithm 2 sequence version

    call prg_timer_start(loop_timer)

    idempotency_tol = 1d-6
    bml_type = "ellpack"
    bndfil = 0.5_dp
    norb = 6144
    mdim = 600
    threshold = 1.0d-9
    sp2tol = 1.0d-10

    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,rho_bml)
    call bml_read_matrix(ham_bml, "poly.512.mtx")

    allocate(pp(100),vv(100))
    icount = 0

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2_genseq(ham_bml, rho_bml, threshold, bndfil, &
                          minsp2iter, maxsp2iter, sp2conv, sp2tol, &
                          pp, icount, vv)

    call prg_sp2_alg2_seq(ham_bml, rho_bml, threshold, pp, icount, vv)
    call prg_timer_stop(sp2_timer)

    deallocate(pp, vv)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg1_seq_inplace_dense") !SP2 algorithm 1 seq version in place

    call prg_timer_start(loop_timer)

    bml_type = "dense"
    call bml_convert_from_dense(bml_type,ham,ham_bml,threshold,norb)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)

    allocate(pp(100),vv(100), gbnd(2))
    icount = 0

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2_genseq(ham_bml, rho_bml, threshold, bndfil, &
                          minsp2iter, maxsp2iter, sp2conv, sp2tol, &
                          pp, icount, vv)
    call prg_timer_stop(sp2_timer)

    call bml_copy(ham_bml, rho_bml)
    call bml_gershgorin(rho_bml, gbnd)

    call prg_timer_start(sp2_timer)
    call prg_prg_sp2_alg1_seq_inplace(rho_bml, threshold, pp, icount, &
                               vv, gbnd(1), gbnd(2))
    call prg_timer_stop(sp2_timer)

    deallocate(pp, vv, gbnd)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg2_seq_inplace_dense") !SP2 algorithm 2 seq version in place

    call prg_timer_start(loop_timer)

    bml_type = "dense"
    call bml_convert_from_dense(bml_type,ham,ham_bml,threshold,norb)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)

    allocate(pp(100),vv(100), gbnd(2))
    icount = 0

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2_genseq(ham_bml, rho_bml, threshold, bndfil, &
                          minsp2iter, maxsp2iter, sp2conv, sp2tol, &
                          pp, icount, vv)
    call prg_timer_stop(sp2_timer)

    call bml_copy(ham_bml, rho_bml)
    call bml_gershgorin(rho_bml, gbnd)

    call prg_timer_start(sp2_timer)
    call prg_prg_sp2_alg2_seq_inplace(rho_bml, threshold, pp, icount, &
                               vv, gbnd(1), gbnd(2))
    call prg_timer_stop(sp2_timer)

    deallocate(pp, vv, gbnd)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_sp2_alg1_seq_inplace_ellpack") !SP2 algorithm 1 seq version in place

    call prg_timer_start(loop_timer)

    idempotency_tol = 1d-6
    bml_type = "ellpack"
    bndfil = 0.5_dp
    norb = 6144
    mdim = 600
    threshold = 1.0d-9
    sp2tol = 1.0d-10

    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,rho_bml)
    call bml_read_matrix(ham_bml, "poly.512.mtx")

    allocate(pp(100),vv(100), gbnd(2))
    icount = 0

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2_genseq(ham_bml, rho_bml, threshold, bndfil, &
                          minsp2iter, maxsp2iter, sp2conv, sp2tol, &
                          pp, icount, vv)
    call prg_timer_stop(sp2_timer)

    call bml_copy(ham_bml, rho_bml)
    call bml_gershgorin(rho_bml, gbnd)

    call prg_timer_start(sp2_timer)
    call prg_prg_sp2_alg1_seq_inplace(rho_bml, threshold, pp, icount, &
                               vv, gbnd(1), gbnd(2))
    call prg_timer_stop(sp2_timer)

    deallocate(pp, vv, gbnd)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)


  case("prg_sp2_alg2_seq_inplace_ellpack") !SP2 algorithm 2 seq version in place

    call prg_timer_start(loop_timer)

    idempotency_tol = 1d-6
    bml_type = "ellpack"
    bndfil = 0.5_dp
    norb = 6144
    mdim = 600
    threshold = 1.0d-9
    sp2tol = 1.0d-10

    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,rho_bml)
    call bml_read_matrix(ham_bml, "poly.512.mtx")

    allocate(pp(100),vv(100), gbnd(2))
    icount = 0

    call prg_timer_start(sp2_timer)
    call prg_sp2_alg2_genseq(ham_bml, rho_bml, threshold, bndfil, &
                          minsp2iter, maxsp2iter, sp2conv, sp2tol, &
                          pp, icount, vv)
    call prg_timer_stop(sp2_timer)

    call bml_copy(ham_bml, rho_bml)
    call bml_gershgorin(rho_bml, gbnd)

    call prg_timer_start(sp2_timer)
    call prg_prg_sp2_alg2_seq_inplace(rho_bml, threshold, pp, icount, &
                               vv, gbnd(1), gbnd(2))
    call prg_timer_stop(sp2_timer)

    deallocate(pp, vv, gbnd)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_equal_partition") ! Create equal partitions

    call prg_timer_start(loop_timer)

    call prg_timer_start(part_timer)
    call prg_equalPartition(gp, 6, 72)
    call prg_timer_stop(part_timer)

    call prg_printGraphPartitioning(gp)
    if (gp%totalParts .ne. 12) then
      write(*,*) "Number of parts is wrong ", gp%totalParts
      call exit(-1)
    endif

    call prg_destroyGraphPartitioning(gp)

    call prg_timer_start(part_timer)
    call prg_equalPartition(gp, 7, 72)
    call prg_timer_stop(part_timer)

    call prg_printGraphPartitioning(gp)
    if (gp%totalParts .ne. 11) then
      write(*,*) "Number of parts is wrong ", gp%totalParts
      !error stop(-1)
      call exit(-1)
    endif

    call prg_timer_stop(loop_timer)

  case("prg_file_partition") ! Create partition from a file

    call prg_timer_start(loop_timer)

    call prg_timer_start(part_timer)
    call prg_filePartition(gp, 'test.part')
    call prg_timer_stop(part_timer)

    call prg_printGraphPartitioning(gp)
    if (gp%totalParts .ne. 104) then
      write(*,*) "Number of parts is wrong ", gp%totalParts
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_subgraphsp2_equal") ! Subgraph SP2 using equal size parts

    call prg_timer_start(loop_timer)

    bml_type = "ellpack"
    norb = 6144
    mdim = 300
    threshold = 1.0d-5
    bndfil = 0.5_dp
    gthreshold = 1.0d-3
    sp2tol = 1.0d-10
    errlimit = 1.0d-12
    nodesPerPart = 48
    idempotency_tol = 1.0d-2

    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,rho_bml)
    call bml_read_matrix(ham_bml, "poly.512.mtx")

    call prg_timer_start(subgraph_timer)
    call test_subgraphloop(ham_bml, rho_bml, threshold, bndfil, &
      minsp2iter, maxsp2iter, sp2conv, sp2tol, gthreshold, errlimit, &
      nodesPerPart)
    call prg_timer_stop(subgraph_timer)

    call bml_scale(0.5_dp, rho_bml)
    call prg_check_idempotency(rho_bml,threshold,idempotency)
    if(idempotency.gt.idempotency_tol)then
      write(*,*) "Idempotency is too high", idempotency
      error stop
    endif

    call prg_timer_stop(loop_timer)

  case("prg_deorthogonalize_dense") !Deorthogonalization of the density matrix

     call prg_timer_start(loop_timer)

     ortho_error_tol = 1.0d-9
     call read_matrix(zmat,norb,'zmatrix.mtx')
     call read_matrix(rho,norb,'density.mtx')
     call read_matrix(rho_ortho,norb,'density_ortho.mtx')

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)
     call bml_convert_from_dense(bml_type,rho,rho_bml,threshold,norb)

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_ortho_bml)
     call bml_convert_from_dense(bml_type,rho_ortho,rho_ortho_bml,threshold,norb)

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,zmat_bml)
     call bml_convert_from_dense(bml_type,zmat,zmat_bml,threshold,norb)

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,aux_bml)

     call prg_timer_start(deortho_timer)
     call prg_deorthogonalize(rho_ortho_bml,zmat_bml,aux_bml,threshold,bml_type,verbose)
     call prg_timer_stop(deortho_timer)

     call bml_add_deprecated(-1.0_dp,aux_bml,1.0_dp,rho_bml,0.0_dp)
     ortho_error = bml_fnorm(aux_bml)

     call bml_deallocate(nonortho_ham_bml)
     call bml_deallocate(zmat_bml)
     call bml_deallocate(aux_bml)

     write(*,*)"prg_orthogonalize error ", ortho_error

     if(ortho_error.gt.ortho_error_tol)then
      write(*,*) "Error is too high", ortho_error
      error stop
     endif

     call prg_timer_stop(loop_timer)

  case("prg_orthogonalize_dense") ! Orthogonalization of the Hamiltonian

     call prg_timer_start(loop_timer)

     ortho_error_tol = 1.0d-9
     bml_type = "dense"

     call read_matrix(zmat,norb,'zmatrix.mtx')
     call read_matrix(nonortho_ham,norb,'hamiltonian.mtx')

     call bml_convert_from_dense(bml_type,ham,ham_bml,threshold,norb)
     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,rho_bml)

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,zmat_bml)
     call bml_convert_from_dense(bml_type,zmat,zmat_bml,threshold,norb)

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,nonortho_ham_bml)

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,aux_bml)
     call bml_convert_from_dense(bml_type,nonortho_ham,nonortho_ham_bml,threshold,norb)

     call prg_timer_start(ortho_timer)
     call prg_orthogonalize(nonortho_ham_bml,zmat_bml,aux_bml,threshold,bml_type,verbose)
     call prg_timer_stop(ortho_timer)

     call bml_add_deprecated(-1.0_dp,aux_bml,1.0_dp,ham_bml,0.0_dp)
     ortho_error = bml_fnorm(aux_bml)

     call bml_deallocate(nonortho_ham_bml)
     call bml_deallocate(zmat_bml)
     call bml_deallocate(aux_bml)

     write(*,*)"Orthogonalize error ", ortho_error

     if(ortho_error.gt.ortho_error_tol)then
      write(*,*) "Error is too high", ortho_error
      error stop
     endif

     call prg_timer_stop(ortho_timer)

  case("prg_buildzdiag")  ! Building inverse overlap factor matrix (Lowdin method)

     call prg_timer_start(loop_timer)

     write(*,*) "Testing buildzdiag from prg_genz_mod"
     error_tol = 1.0d-9
     bml_type = "dense"

     call read_matrix(zmat,norb,'zmatrix.mtx')
     call read_matrix(over,norb,'overlap.mtx')

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,zmat_bml)
     call bml_convert_from_dense(bml_type,zmat,zmat_bml,threshold,norb)

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,over_bml)
     call bml_convert_from_dense(bml_type,over,over_bml,threshold,norb)

     call bml_zero_matrix(bml_type,bml_element_real,dp,norb,norb,aux_bml)
!
     call prg_timer_start(zdiag_timer)
     call prg_buildzdiag(over_bml,aux_bml,threshold,norb,bml_type)
     call prg_timer_stop(zdiag_timer)

     call bml_add_deprecated(-1.0_dp,aux_bml,1.0_dp,zmat_bml,0.0_dp)

     error_calc = bml_fnorm(aux_bml)

     if(error_calc.gt.error_tol)then
      write(*,*) "Error is too high", error_calc
      error stop
     endif

     call prg_timer_stop(loop_timer)


  case("prg_system_parse_write_xyz")
    call prg_parse_system(mol,"coords_100","xyz")
    call prg_write_system(mol, "mysystem","xyz")
    call system("diff -qs  mysystem.xyz coords_100.xyz > tmp.tmp")
    open(1,file="tmp.tmp")
    read(1,*)dummy(1),dummy(2),dummy(3),dummy(4),dummy(5)
    if(trim(dummy(5)).EQ."differ")then
      write(*,*) "Error coords are not the same"
      error stop
    endif

  case("prg_system_parse_write_pdb")
    call prg_parse_system(mol,"protein","pdb")
    call prg_write_system(mol, "mysystem","pdb")
    call system("diff -qs  mysystem.pdb protein.pdb > tmp.tmp")
    open(1,file="tmp.tmp")
    read(1,*)dummy(1),dummy(2),dummy(3),dummy(4),dummy(5)
    if(trim(dummy(5)).EQ."differ")then
      write(*,*) "Error coords are not the same"
      error stop
    endif

  case("prg_system_parse_write_dat")
    call prg_parse_system(mol,"inputblock","dat")
    call prg_write_system(mol, "mysystem","dat")
    call system("diff -qs  mysystem.dat inputblock.dat > tmp.tmp")
    open(1,file="tmp.tmp")
    read(1,*)dummy(1),dummy(2),dummy(3),dummy(4),dummy(5)
    if(trim(dummy(5)).EQ."differ")then
      write(*,*) "Error coords are not the same"
      error stop
    endif

!---------------------------------------------
!LATTE routines
!---------------------------------------------

  case("load_tbparms_latte")
    call prg_parse_system(mol,"protein","pdb")
    !> Loading the tb parameters (electrons.dat)
    call load_latteTBparams(tbparams,mol%splist,"./")
    call write_latteTBparams(tbparams,"myelectrons.dat")
    call system("diff -qs  myelectrons.dat electrons.dat > tmp.tmp")
    open(1,file="tmp.tmp")
    read(1,*)dummy(1),dummy(2),dummy(3),dummy(4),dummy(5)
    if(trim(dummy(5)).EQ."differ")then
      write(*,*) "Error tbparams are not the same"
      error stop
    endif

  case("load_bintTBparamsH")
    call prg_parse_system(mol,"protein","pdb")
    !> Loading the bint parameters (bondints.nonorth)
    call load_latteTBparams(tbparams,mol%splist,"./")
    call load_bintTBparamsH(mol%splist,tbparams%onsite_energ,&
    typeA,typeB,intKind,onsitesH,onsitesS,intPairsH,intPairsS,"./")
    call write_bintTBparamsH(typeA,typeB,&
      intKind,intPairsH,intPairsS,"mybondints.nonorth")
    call system("diff -qs  mybondints.nonorth bondints.nonorth > tmp.tmp")
    open(1,file="tmp.tmp")
    read(1,*)dummy(1),dummy(2),dummy(3),dummy(4),dummy(5)
    if(trim(dummy(5)).EQ."differ")then
      write(*,*) "Error bond int tbparams are not the same"
      error stop
    endif

  case("get_hshuckel")
    call prg_parse_system(mol,"coords_100","xyz") !Reads the system coordinate.
    !> Get the huckel hamiltonian and overlap
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,ham_bml)
    call bml_zero_matrix(bml_type,bml_element_real,dp,norb,mdim,over_bml)
    call get_hshuckel(ham_bml,over_bml,mol%coordinate,mol%spindex,mol%spatnum,&
    "./",bml_type,mdim,threshold&
    ,tbparams%nsp,tbparams%splist,tbparams%basis,tbparams%numel,tbparams%onsite_energ,&
    tbparams%norbi,tbparams%hubbardu)
    call bml_write_matrix(ham_bml,"huckel_ham.mtx")
    call system("diff -qs  huckel_ham.mtx huckel_ham_ref.mtx > tmp.tmp")
    open(1,file="tmp.tmp")
    read(1,*)dummy(1),dummy(2),dummy(3),dummy(4),dummy(5)
    if(trim(dummy(5)).EQ."differ")then
      write(*,*) "Error bond int tbparams are not the same"
      error stop
    endif


  case default

    write(*,*)"ERROR: unknown test ",test
    error stop

  end select

  ! Shutdown progress
  call prg_progress_shutdown()

  call exit(0)

end program main
