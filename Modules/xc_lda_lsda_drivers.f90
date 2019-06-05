!
! Copyright (C) 2004-2016 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!
MODULE xc_lda_lsda
!
USE kinds,     ONLY: DP 
!
IMPLICIT NONE
!
PRIVATE
SAVE
!
!  LDA and LSDA exchange-correlation drivers
PUBLIC :: xc, xc_lda, xc_lsda, select_lda_functionals
!
PUBLIC :: libxc_switches_lda
PUBLIC :: iexch_l, icorr_l
PUBLIC :: exx_started_l, exx_fraction_l
PUBLIC :: is_there_finite_size_corr, finite_size_cell_volume_l
!
!  use qe or libxc for the different terms (0: qe, 1: libxc)
INTEGER :: libxc_switches_lda(2)
!
!  indexes defining xc functionals
INTEGER  :: iexch_l, icorr_l
!
!  variables for hybrid exchange and finite_size_cell_volume correction
LOGICAL  :: exx_started_l, is_there_finite_size_corr
REAL(DP) :: exx_fraction_l, finite_size_cell_volume_l
!
!
 CONTAINS
!
!
!----------------------------------------------------------------------------
!----- Select functionals by the corresponding indexes ----------------------
!----------------------------------------------------------------------------
SUBROUTINE select_lda_functionals( iexch, icorr, exx_fraction, finite_size_cell_volume )
   !
   IMPLICIT NONE
   !
   INTEGER,  INTENT(IN) :: iexch, icorr
   REAL(DP), INTENT(IN), OPTIONAL :: exx_fraction, finite_size_cell_volume
   !
   ! exchange-correlation indexes
   iexch_l = iexch
   icorr_l = icorr
   !
   ! hybrid exchange vars
   exx_started_l  = .FALSE.
   exx_fraction_l = 0._DP
   IF ( PRESENT(exx_fraction) ) THEN
      exx_started_l  = .TRUE.
      exx_fraction_l = exx_fraction
   ENDIF
   !
   ! finite size correction vars
   is_there_finite_size_corr = .FALSE.
   finite_size_cell_volume_l = -1.0_DP
   IF ( PRESENT(finite_size_cell_volume) ) THEN
      is_there_finite_size_corr = .TRUE.
      finite_size_cell_volume_l = finite_size_cell_volume
   ENDIF
   !
   !
   RETURN
   !
END SUBROUTINE select_lda_functionals
!
!
!---------------------------------------------------------------------------
SUBROUTINE xc( length, sr_d, sv_d, rho_in, ex_out, ec_out, vx_out, vc_out )
  !-------------------------------------------------------------------------
  !! Wrapper routine. Calls xc-driver routines from internal libraries
  !! of q-e or from the external libxc, depending on the input choice.
  !
  !! NOTE: look at 'PP/src/benchmark_libxc.f90' to see the differences
  !!       between q-e and libxc.
  !
#if defined(__LIBXC)
  USE xc_f90_types_m
  USE xc_f90_lib_m
#endif
  !
  IMPLICIT NONE
  !
  INTEGER,  INTENT(IN) :: length
  !! length of the I/O arrays
  INTEGER,  INTENT(IN) :: sr_d
  !! spin dimension of rho
  INTEGER, INTENT(IN) :: sv_d
  !! spin dimension of v
  REAL(DP), INTENT(IN) :: rho_in(length,sr_d)
  !! Charge density
  REAL(DP), INTENT(OUT) :: ex_out(length)
  !! \(\epsilon_x(rho)\) ( NOT \(E_x(\text{rho})\) )
  REAL(DP), INTENT(OUT) :: vx_out(length,sv_d)
  !! \(dE_x(\text{rho})/d\text{rho}  ( NOT d\epsilon_x(\text{rho})/d\text{rho} )
  REAL(DP), INTENT(OUT) :: ec_out(length)
  !! \(\epsilon_c(rho)\) ( NOT \(E_c(\text{rho})\) )
  REAL(DP), INTENT(OUT) :: vc_out(length,sv_d)
  !! \(dE_c(\text{rho})/d\text{rho}  ( NOT d\epsilon_c(\text{rho})/d\text{rho} )
  !
  ! ... local variables
  !
#if defined(__LIBXC)
  TYPE(xc_f90_pointer_t) :: xc_func
  TYPE(xc_f90_pointer_t) :: xc_info1, xc_info2
  REAL(DP) :: amag
  REAL(DP), ALLOCATABLE :: rho_lxc(:)
  REAL(DP), ALLOCATABLE :: vx_lxc(:), vc_lxc(:)
#endif
  !
  REAL(DP), ALLOCATABLE :: arho(:), zeta(:)
  !
  INTEGER :: ir
  REAL(DP), PARAMETER :: small = 1.E-10_DP
  !
  !
#if defined(__LIBXC)
  !
  IF (SUM(libxc_switches_lda) /= 0) THEN
    !
    ALLOCATE( rho_lxc(length*sv_d) )
    ALLOCATE( vx_lxc(length*sv_d), vc_lxc(length*sv_d) )
    !
    ! ... set libxc input
    SELECT CASE( sr_d )
    CASE( 1 )
       !
       rho_lxc(:) = rho_in(:,1)
       !
    CASE( 2 )
       !
       DO ir = 1, length
          rho_lxc(2*ir-1) = (rho_in(ir,1) + rho_in(ir,2)) * 0.5_DP
          rho_lxc(2*ir)   = (rho_in(ir,1) - rho_in(ir,2)) * 0.5_DP
       ENDDO
       !
    CASE( 4 )
       !
       DO ir = 1, length
          amag = SQRT( SUM(rho_in(ir,2:4)**2) )
          rho_lxc(2*ir-1) = (rho_in(ir,1) + amag) * 0.5_DP
          rho_lxc(2*ir)   = (rho_in(ir,1) - amag) * 0.5_DP
       ENDDO
       !
    CASE DEFAULT
       !
       CALL errore( 'xc_LDA', 'Wrong number of spin dimensions', 1 )
       !
    END SELECT
    !
  ENDIF
  !
  !
  ! ... EXCHANGE
  IF ( libxc_switches_lda(1)==1 ) THEN
     CALL xc_f90_func_init( xc_func, xc_info1, iexch_l, sv_d )
       CALL xc_f90_lda_exc_vxc( xc_func, length, rho_lxc(1), ex_out(1), vx_lxc(1) )
     CALL xc_f90_func_end( xc_func )
  ENDIF
  !
  ! ... CORRELATION
  IF ( libxc_switches_lda(2)==1 ) THEN
     CALL xc_f90_func_init( xc_func, xc_info2, icorr_l, sv_d )
      CALL xc_f90_lda_exc_vxc( xc_func, length, rho_lxc(1), ec_out(1), vc_lxc(1) )
     CALL xc_f90_func_end( xc_func )
  ENDIF
  !
  !
  IF ( (libxc_switches_lda(1)==0) .OR. (libxc_switches_lda(2)==0) ) THEN
     !
     SELECT CASE( sr_d )
     CASE( 1 )
        !
        CALL xc_lda( length, ABS(rho_in(:,1)), ex_out, ec_out, vx_out(:,1), vc_out(:,1) )
        !
     CASE( 2 )
        !
        ALLOCATE( arho(length), zeta(length) )
        arho = ABS(rho_in(:,1))
        WHERE (arho > small) zeta(:) = rho_in(:,2) / arho(:)
        CALL xc_lsda( length, arho, zeta, ex_out, ec_out, vx_out, vc_out )
        DEALLOCATE( arho, zeta )
        !
     CASE( 4 )
        !
        ALLOCATE( arho(length), zeta(length) )
        arho = ABS( rho_in(:,1) )
        WHERE (arho > small) zeta(:) = SQRT( rho_in(:,2)**2 + rho_in(:,3)**2 + &
                                             rho_in(:,4)**2 ) / arho(:) ! amag/arho
        CALL xc_lsda( length, arho, zeta, ex_out, ec_out, vx_out, vc_out )
        DEALLOCATE( arho, zeta )
        !
     CASE DEFAULT
        !
        CALL errore( 'xc_LDA', 'Wrong ns input', 2 )
        !
     END SELECT
     !
  ENDIF
  !
  !  ... fill output arrays
  !  
  IF (sv_d == 1) THEN
     IF (libxc_switches_lda(1)==1) vx_out(:,1) = vx_lxc(:)
     IF (libxc_switches_lda(2)==1) vc_out(:,1) = vc_lxc(:)
  ELSE
     IF (libxc_switches_lda(1)==1) THEN
        DO ir = 1, length
           vx_out(ir,1) = vx_lxc(2*ir-1)
           vx_out(ir,2) = vx_lxc(2*ir)
        ENDDO
     ENDIF
     IF (libxc_switches_lda(2)==1) THEN
        DO ir = 1, length
           vc_out(ir,1) = vc_lxc(2*ir-1)
           vc_out(ir,2) = vc_lxc(2*ir)
        ENDDO
     ENDIF
  ENDIF
  !
  IF (SUM(libxc_switches_lda) /= 0) THEN
     DEALLOCATE( rho_lxc )
     DEALLOCATE( vx_lxc, vc_lxc )
  ENDIF
  !
#else
  !
  SELECT CASE( sr_d )
  CASE( 1 )
     !
     CALL xc_lda( length, ABS(rho_in(:,1)), ex_out, ec_out, vx_out(:,1), vc_out(:,1) )
     !
  CASE( 2 )
     !
     ALLOCATE( arho(length), zeta(length) )
     !
     arho = ABS(rho_in(:,1))
     WHERE (arho > small) zeta(:) = rho_in(:,2) / arho(:)
     !
     CALL xc_lsda( length, arho, zeta, ex_out, ec_out, vx_out, vc_out )
     !
     DEALLOCATE( arho, zeta )
     ! 
  CASE( 4 )
     !
     ALLOCATE( arho(length), zeta(length) )
     !
     arho = ABS( rho_in(:,1) )
     WHERE (arho > small) zeta(:) = SQRT( rho_in(:,2)**2 + rho_in(:,3)**2 + &
                                          rho_in(:,4)**2 ) / arho(:) ! amag/arho
     !
     CALL xc_lsda( length, arho, zeta, ex_out, ec_out, vx_out, vc_out )
     !
     DEALLOCATE( arho, zeta )
     !
  CASE DEFAULT
     !
     CALL errore( 'xc_LDA', 'Wrong ns input', 2 )
     !
  END SELECT
  !
#endif
  !
  !
  RETURN
  !
END SUBROUTINE xc
!
!----------------------------------------------------------------------------
!-------  LDA-LSDA DRIVERS --------------------------------------------------
!----------------------------------------------------------------------------
!
!----------------------------------------------------------------------------
SUBROUTINE xc_lda( length, rho_in, ex_out, ec_out, vx_out, vc_out )
  !--------------------------------------------------------------------------
  !! LDA exchange and correlation functionals - Hartree a.u.
  !
  !! * Exchange:
  !!    * Slater;
  !!    * relativistic Slater.
  !! * Correlation:
  !!    * Ceperley-Alder (Perdew-Zunger parameters);
  !!    * Vosko-Wilk-Nusair;
  !!    * Lee-Yang-Parr;
  !!    * Perdew-Wang;
  !!    * Wigner;
  !!    * Hedin-Lundqvist;
  !!    * Ortiz-Ballone (Perdew-Zunger formula);
  !!    * Ortiz-Ballone (Perdew-Wang formula);
  !!    * Gunnarsson-Lundqvist.
  !
  !! NOTE:
  !! $$ E_x = \int E_x(\text{rho}) dr, E_x(\text{rho}) = 
  !!               \text{rho}\epsilon_c(\text{rho})\ . $$
  !! Same for correlation.
  !
  IMPLICIT NONE
  !
  INTEGER,  INTENT(IN) :: length
  !! length of the I/O arrays
  REAL(DP), INTENT(IN),  DIMENSION(length) :: rho_in
  !! Charge density
  REAL(DP), INTENT(OUT), DIMENSION(length) :: ex_out
  !! \(\epsilon_x(rho)\) ( NOT \(E_x(\text{rho})\) )
  REAL(DP), INTENT(OUT), DIMENSION(length) :: vx_out
  !! \(dE_x(\text{rho})/d\text{rho}\)  ( NOT \(d\epsilon_x(\text{rho})/d\text{rho}\) )
  REAL(DP), INTENT(OUT), DIMENSION(length) :: ec_out
  !! \(\epsilon_c(rho)\) ( NOT \(E_c(\text{rho})\) )
  REAL(DP), INTENT(OUT), DIMENSION(length) :: vc_out
  !! \(dE_c(\text{rho})/d\text{rho}\)  ( NOT \(d\epsilon_c(\text{rho})/d\text{rho}\) )
  !
  ! ... local variables
  !
  INTEGER  :: ir
  REAL(DP) :: rho, rs
  REAL(DP) :: ex, ec, ec_
  REAL(DP) :: vx, vc, vc_
  REAL(DP), PARAMETER :: small = 1.E-10_DP,  third = 1.0_DP/3.0_DP, &
                         pi34 = 0.6203504908994_DP, e2 = 2.0_DP
  !                      pi34 = (3/4pi)^(1/3)
  !
#if defined(_OPENMP)
  INTEGER :: ntids
  INTEGER, EXTERNAL :: omp_get_num_threads
  !
  ntids = omp_get_num_threads()
#endif
  !
!$omp parallel if(ntids==1)
!$omp do private( rho, rs, ex, ec, ec_, vx, vc, vc_ )
  DO ir = 1, length
     !
     rho = ABS(rho_in(ir))
     !
     ! ... RHO THRESHOLD
     !
     IF ( rho > small ) THEN
        rs = pi34 / rho**third
     ELSE
        ex_out(ir) = 0.0_DP  ;  ec_out(ir) = 0.0_DP
        vx_out(ir) = 0.0_DP  ;  vc_out(ir) = 0.0_DP
        CYCLE
     ENDIF
     !
     ! ... EXCHANGE
     !
     SELECT CASE( iexch_l )
     CASE( 1 )                      ! 'sla'
        !
        CALL slater( rs, ex, vx )
        !
     CASE( 2 )                      ! 'sl1'
        !
        CALL slater1( rs, ex, vx )
        !
     CASE( 3 )                      ! 'rxc'
        !
        CALL slater_rxc( rs, ex, vx )
        !
     CASE( 4, 5 )                   ! 'oep','hf'
        !
        IF ( exx_started_l ) THEN
           ex = 0.0_DP
           vx = 0.0_DP
        ELSE
           CALL slater( rs, ex, vx )
        ENDIF
        !
     CASE( 6, 7 )                   ! 'pb0x' or 'DF-cx-0', or 'DF2-0',
        !                           ! 'B3LYP'
        CALL slater( rs, ex, vx )
        IF ( exx_started_l ) THEN
           ex = (1.0_DP - exx_fraction_l) * ex
           vx = (1.0_DP - exx_fraction_l) * vx
        ENDIF
        !
     CASE( 8 )                      ! 'sla+kzk'
        !
        IF (.NOT. is_there_finite_size_corr) CALL errore( 'XC',&
             'finite size corrected exchange used w/o initialization', 2 )
        CALL slaterKZK( rs, ex, vx, finite_size_cell_volume_l )
        !
     CASE( 9 )                      ! 'X3LYP'
        !
        CALL slater( rs, ex, vx )
        IF ( exx_started_l ) THEN
           ex = (1.0_DP - exx_fraction_l) * ex
           vx = (1.0_DP - exx_fraction_l) * vx
        ENDIF
        !
     CASE DEFAULT
        !
        ex = 0.0_DP
        vx = 0.0_DP
        !
     END SELECT
     !
     !
     ! ... CORRELATION
     !
     SELECT CASE( icorr_l )
     CASE( 1 )
        !
        CALL pz( rs, 1, ec, vc )
        !
     CASE( 2 )
        !
        CALL vwn( rs, ec, vc )
        !
     CASE( 3 )
        !
        CALL lyp( rs, ec, vc )
        !
     CASE( 4 )
        !
        CALL pw( rs, 1, ec, vc )
        !
     CASE( 5 )
        !
        CALL wignerc( rs, ec, vc )
        !
     CASE( 6 )
        !
        CALL hl( rs, ec, vc )
        !
     CASE( 7 )
        !
        CALL pz( rs, 2, ec, vc )
        ! 
     CASE( 8 )
        !
        CALL pw( rs, 2, ec, vc )
        !
     CASE( 9 )
        !
        CALL gl( rs, ec, vc )
        !
     CASE( 10 )
        !
        IF (.NOT. is_there_finite_size_corr) CALL errore( 'XC',&
             'finite size corrected exchange used w/o initialization', 3 )
        CALL pzKZK( rs, ec, vc, finite_size_cell_volume_l )
        !
     CASE( 11 )
        !
        CALL vwn1_rpa( rs, ec, vc )
        !
     CASE( 12 )                ! 'B3LYP'
        !
        CALL vwn( rs, ec, vc )
        ec = 0.19_DP * ec
        vc = 0.19_DP * vc
        !
        CALL lyp( rs, ec_, vc_ )
        ec = ec + 0.81_DP * ec_
        vc = vc + 0.81_DP * vc_
        !
     CASE( 13 )                ! 'B3LYP-V1R'
        !
        CALL vwn1_rpa ( rs, ec, vc )
        ec = 0.19_DP * ec
        vc = 0.19_DP * vc
        !
        CALL lyp( rs, ec_, vc_ )
        ec = ec + 0.81_DP * ec_
        vc = vc + 0.81_DP * vc_
        !
     CASE( 14 )                ! 'X3LYP'
        !
        CALL vwn1_rpa( rs, ec, vc )
        ec = 0.129_DP * ec
        vc = 0.129_DP * vc
        !
        CALL lyp( rs, ec_, vc_ )
        ec = ec + 0.871_DP * ec_
        vc = vc + 0.871_DP * vc_
        !
     CASE DEFAULT
        !
        ec = 0.0_DP
        vc = 0.0_DP
        !
     END SELECT
     !
     ex_out(ir) = ex  ;  ec_out(ir) = ec
     vx_out(ir) = vx  ;  vc_out(ir) = vc
     !
  ENDDO
!$omp end do
!$omp end parallel
  !
  !
  RETURN
  !
END SUBROUTINE xc_lda
!
!
!-----------------------------------------------------------------------------
SUBROUTINE xc_lsda( length, rho_in, zeta_in, ex_out, ec_out, vx_out, vc_out )
  !-----------------------------------------------------------------------------
  !! LSD exchange and correlation functionals - Hartree a.u.
  !
  !! * Exchange:
  !!    * Slater (alpha=2/3).
  !! * Correlation:
  !!    * Ceperley & Alder (Perdew-Zunger parameters);
  !!    * Perdew & Wang.
  !
  IMPLICIT NONE
  !
  INTEGER,  INTENT(IN) :: length
  !! length of the I/O arrays
  REAL(DP), INTENT(IN),  DIMENSION(length) :: rho_in
  !! Total charge density
  REAL(DP), INTENT(IN),  DIMENSION(length) :: zeta_in
  !! zeta = mag / rho_tot
  REAL(DP), INTENT(OUT), DIMENSION(length) :: ex_out
  !! \(\epsilon_x(rho)\) ( NOT \(E_x(\text{rho})\) )
  REAL(DP), INTENT(OUT), DIMENSION(length) :: ec_out
  !! \(\epsilon_c(rho)\) ( NOT \(E_c(\text{rho})\) )
  REAL(DP), INTENT(OUT), DIMENSION(length,2) :: vx_out
  !! \(dE_x(\text{rho})/d\text{rho}\)  ( NOT \(d\epsilon_x(\text{rho})/d\text{rho}\) )
  REAL(DP), INTENT(OUT), DIMENSION(length,2) :: vc_out
  !! \(dE_c(\text{rho})/d\text{rho}\)  ( NOT \(d\epsilon_c(\text{rho})/d\text{rho}\) )
  !
  ! ...  local variables
  !
  INTEGER  :: ir
  REAL(DP) :: rho, rs, zeta
  REAL(DP) :: ex, ec, ec_
  REAL(DP) :: vx(2), vc(2), vc_(2)
  !
  REAL(DP), PARAMETER :: small= 1.E-10_DP, third = 1.0_DP/3.0_DP, &
                         pi34 = 0.6203504908994_DP
  !                      pi34 = (3/4pi)^(1/3)
  !
#if defined(_OPENMP)
  INTEGER :: ntids
  INTEGER, EXTERNAL :: omp_get_num_threads
  !
  ntids = omp_get_num_threads()
#endif
  !
!$omp parallel if(ntids==1)
!$omp do private( rho, rs, zeta, ex, ec, ec_, vx, vc, vc_ )
  DO ir = 1, length
     !
     zeta = zeta_in(ir)
     IF (ABS(zeta) > 1.D0) zeta = SIGN( 1.D0, zeta )
     !
     rho = ABS(rho_in(ir))
     !
     IF ( rho > small ) THEN
        rs = pi34 / rho**third
     ELSE
        ex_out(ir) = 0.0_DP  ;  vx_out(ir,:) = 0.0_DP
        ec_out(ir) = 0.0_DP  ;  vc_out(ir,:) = 0.0_DP
        CYCLE
     ENDIF
     !
     !
     ! ... EXCHANGE
     !
     SELECT CASE( iexch_l )
     CASE( 1 )                                      ! 'sla'
        !
        CALL slater_spin( rho, zeta, ex, vx )
        !
     CASE( 2 )                                      ! 'sl1'
        !
        CALL slater1_spin( rho, zeta, ex, vx )
        !
     CASE( 3 )                                      ! 'rxc'
        !
        CALL slater_rxc_spin( rho, zeta, ex, vx )
        !
     CASE( 4, 5 )                                   ! 'oep','hf'
        !
        IF ( exx_started_l ) THEN
           ex = 0.0_DP
           vx = 0.0_DP
        ELSE
           CALL slater_spin( rho, zeta, ex, vx )
        ENDIF
        !
     CASE( 6 )                                      ! 'pb0x'
        !
        CALL slater_spin( rho, zeta, ex, vx )
        IF ( exx_started_l ) THEN
           ex = (1.0_DP - exx_fraction_l) * ex
           vx = (1.0_DP - exx_fraction_l) * vx
        ENDIF
        !
     CASE( 7 )                                      ! 'B3LYP'
        !
        CALL slater_spin( rho, zeta, ex, vx )
        IF ( exx_started_l ) THEN
           ex = (1.0_DP - exx_fraction_l) * ex
           vx = (1.0_DP - exx_fraction_l) * vx
        ENDIF
        !
     CASE( 9 )                                      ! 'X3LYP'
        !
        CALL slater_spin( rho, zeta, ex, vx )
        IF ( exx_started_l ) THEN
           ex = (1.0_DP - exx_fraction_l) * ex
           vx = (1.0_DP - exx_fraction_l) * vx
        ENDIF
        !
     CASE DEFAULT
        !
        ex = 0.0_DP
        vx = 0.0_DP
        !
     END SELECT
     !
     !
     ! ... CORRELATION
     !
     SELECT CASE( icorr_l )
     CASE( 0 )
        !
        ec = 0.0_DP
        vc = 0.0_DP
        !
     CASE( 1 )
        !
        CALL pz_spin( rs, zeta, ec, vc )
        !
     CASE( 2 )
        !
        CALL vwn_spin( rs, zeta, ec, vc )
        !
     CASE( 3 )
        !
        CALL lsd_lyp( rho, zeta, ec, vc )                 ! from CP/FPMD (more_functionals)
        !
     CASE( 4 )
        !
        CALL pw_spin( rs, zeta, ec, vc )
        !
     CASE( 12 )                                           ! 'B3LYP'
        !
        CALL vwn_spin( rs, zeta, ec, vc )
        ec = 0.19_DP * ec
        vc = 0.19_DP * vc
        !
        CALL lsd_lyp( rho, zeta, ec_, vc_ )               ! from CP/FPMD (more_functionals)
        ec = ec + 0.81_DP * ec_
        vc = vc + 0.81_DP * vc_
        !     
     CASE( 13 )                                           ! 'B3LYP-V1R'
        !
        CALL vwn1_rpa_spin( rs, zeta, ec, vc )
        ec = 0.19_DP * ec
        vc = 0.19_DP * vc
        !
        CALL lsd_lyp( rho, zeta, ec_, vc_ )               ! from CP/FPMD (more_functionals)
        ec = ec + 0.81_DP * ec_
        vc = vc + 0.81_DP * vc_
        !
     CASE( 14 )                                           ! 'X3LYP
        !
        CALL vwn1_rpa_spin( rs, zeta, ec, vc )
        ec = 0.129_DP * ec
        vc = 0.129_DP * vc
        !
        CALL lsd_lyp( rho, zeta, ec_, vc_ )               ! from CP/FPMD (more_functionals)
        ec = ec + 0.871_DP * ec_
        vc = vc + 0.871_DP * vc_
        !
     CASE DEFAULT
        !
        CALL errore( 'xc_lda_lsda_drivers (xc_lsda)', 'not implemented', icorr_l )
        !
     END SELECT
     !
     ex_out(ir) = ex  ;  vx_out(ir,:) = vx(:)
     ec_out(ir) = ec  ;  vc_out(ir,:) = vc(:)
     !
  ENDDO
!$omp end do
!$omp end parallel
  !
  !
  RETURN
  !
END SUBROUTINE xc_lsda
!
!
END MODULE xc_lda_lsda
