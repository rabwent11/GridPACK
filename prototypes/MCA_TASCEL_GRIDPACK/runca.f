!------------------------------------------
!                                    
!           CONTINGENCY ANALYSIS         
!                                     
!------------------------------------------
!
!      THIS PROGRAM READS AN CONTINGENCY LIST FILES AND DOES
!      CONTINGENCY ANALYSIS
!
!------------------------------------------
!
!      AUTHOR:        YOUSU CHEN
!      DATE:          06/05/2007
!      LAST MODIFIED: 08/03/2007
!      $ID V1.02 2007/8/03
!-------------------------------------------
!       REVISION LOG:
!
!     06/05/2007
!     THIS PROGRAM IS MODIFED FROM RUNPF.F (POWER FLOW SIMULATION)

!     07/30/2007
!     MPI IS IMPLEMENTED

!     08/03/2007
!     ARMCI IS IMPLEMENTED

!     02/14/2008
!     RECORD THREE TYPES OF CA CASES
!     1. DIVERGENCE
!     2. VIOLATION
!     3. NO VIOLATION

!     03/30/2009
!     1. MODIFED THE CODE TO DEAL WITH BRANCH OUTAGE ONLY, THE "CALIST" FILE
!        WILL ONLY CONTAIN THE BRANCH INDEX INFORMATION 
!     2. CHANGED THE ARCHIVED DIRECTORY OF OUTPUT FILES, FROM /SCRATCH/ TO OUTPUT
!     3. ONLY N-1 IS IMPLEMENTED FOR NOW. I WILL INTEGRATE COMPRESSED BINARY FILE AND DO N-2/N-3 LATER 

!      PROGRAM RUNCA
      SUBROUTINE RUNCA

      USE BUSMODULE
      USE GENMODULE
      USE BRCHMODULE
      USE YBUSMODULE
      USE OTHERMODULE
      USE CAMODULE
      USE CLOCK
      USE SUBS
      USE FLAGS
      USE MPI
      
      IMPLICIT NONE
      
      INTEGER :: I,J
!      INTEGER :: I,J,ITER,CONVERGED,IFMT,SOLOPT,STARTOPT
!      INTEGER, PARAMETER :: MAX_IT = 20, ! MAXIMUM ITERATION NUMBER
!     &          ISOLATE = 0  ! IF THERE IS ISOLATE BUS, SET ISOLATE = 1      
!      REAL(KIND=DP), PARAMETER :: TOL = 1.0E-8
      CHARACTER*5 :: NUM2STRME
      CHARACTER*100 :: BUFFER

!      INTEGER :: DUMMY,ICA,BUF_L,FNLENG
!      EXTERNAL COUNTERS_INC
  
!       
!     -------------- END OF DECLARATION  -------------
!

!
!     -------------- PROGRAM STARTS HERE -------------
!
!     RUN POWER FLOW ONCE, SAVE YBUS AND P/Q INFORMATION, THEN DO CA
!
      CALL MPI_INIT(IERR)
      CALL MPI_COMM_SIZE(MPI_COMM_WORLD,NPROC,IERR)
      CALL MPI_COMM_RANK(MPI_COMM_WORLD,ME,IERR)
      CALL COUNTERS_CREATE()

!
!     READ CONFIG
!
      CALL READCONFIGFILE

      FN=''
      NUM2STRME=''
      ICOUNT=-1

!     PARAMETER SETUP
      IFMT = 2
      SOLOPT=2
      GENOPT = 0
!
! --- GET ARRAY SIZES
!
      
      CALL READSIZE(INPUTFILE)

!
! --- ALLOCATE MEMORY FOR ALL ARRAYS
! 
      CALL ALLOC

!      
! --- READ MODEL FILE
!
      T0 = MPI_WTIME()
      CALL READMODEL
      T1 = MPI_WTIME()
      IF (ME.EQ.0) PRINT *, 'READINPUT SPENT ',T1-T0
!
! -- SAVE INITIAL MODEL VALUES
!
      CALL SAVEINI

      CALL EXT2INT
!
! ----GET PV ARRAY, PQ ARRAY, AND SLACK BUS
!
      CALL BUSTYPES
!
!
! --- MAKE GBUS -- (FIND THE BUS NUMBER OF THE GENERATORS ARE ON)
!
      CALL MAKEGBUS

      CALL FLATSTART 
!
! ---  MAKE YBUS  -----------
!
      CALL MAKEYBUS
      
      IF(ME.EQ.0) CALL CHKYBUS
!
!     ---------  MAKE SBUS  -----------
!    
      CALL MAKESBUS
!
!
!     ---------- NEWTON'S METHOD --------------
!     
      T0 = MPI_WTIME()
      CALL NEWTONPF
      T1 = MPI_WTIME()
      IF (ME.EQ.0) PRINT *, 'NEWTONPF SPENT ', T1-T0
!
!---- UPDATE BUS, GENERATOR, BRANCH DATA -------------
!      
      T0 = MPI_WTIME()
      CALL PFSOLN   
      T1 = MPI_WTIME()
      IF (ME.EQ.0) PRINT *, 'PFSOLN SPENT ', T1-T0

      CALL SAVEPF

      CALL LIMIT
!
!---- CONVERT INTERNAL NODES TO ORIGNAL EXTERNAL NODES -----
!
      CALL INT2EXT 
!
!---- WRITE RESULTS INTO 'PFRESULT.OUT' FILE -------
!
      IF (ME.EQ.0) CALL PRINTPF
!
!---------- POWER FLOW ENDS HERE ----------
!
!
!--------- CONTINGENCY ANALYSIS STARTS HERE ----------------------     
!
!     
      IF (M.LE.2) THEN

        IF (ME.EQ.0) CALL PRINTCAHEADER 
   
        CALL ALLOCCA
!
        IF (CAOPT.EQ.1) THEN
           IF (M.NE.0) CALL READCALIST2(CAFILE,SEL_BRID,NCA)
           IF (M.EQ.0) CALL READCALISTNEW(CAFILE,CA_INDEX, N_OF_CA, 
     & CA_NAME, CA_BRID, CA_FROM, CA_TO, CA_IROW, NCA) 
        ENDIF

        CALL MPI_BARRIER(MPI_COMM_WORLD,IERR);

        CALL CREATEFILENAMES

        NVIO=0
        NDIV=0 
        NOK=0
        CASEFLAG=''
        SUMALL=0.0
        SUMCOMP=0.0
        SUMIO=0.0

        CALL MPI_BARRIER(MPI_COMM_WORLD,IERR);

        T0 = MPI_WTIME()
        CALL COUNTERS_PROCESS(NCAN);
        T1 = MPI_WTIME()

        CALL MPI_BARRIER(MPI_COMM_WORLD,IERR)
        WRITE(4,FMT=110) SUMALL, SUMIO, SUMCOMP
  110   FORMAT(2X,3(G12.5,2X))
        IF (ME .EQ.0 ) PRINT *,'PROC #   T_ALL     T_CMP     T_IO      
     &#_D    #_V    #_N   #_TOTAL'
        WRITE(*,'(I5,1X,3(F10.4),4(1X,I6))') ME,SUMALL,SUMCOMP,SUMIO,
     &        NDIV,NVIO,NOK,NDIV+NVIO+NOK
      ELSE
        IF (ME.EQ.0) PRINT *, 'POWERFLOW IS COMPLETED'
      ENDIF
        CALL COUNTERS_DESTROY()
        CALL MPI_BARRIER(MPI_COMM_WORLD,IERR)
        CALL MPI_FINALIZE(IERR)

      ENDSUBROUTINE
