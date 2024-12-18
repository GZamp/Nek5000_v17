c-----------------------------------------------------------------------
c   CASE PARAMETERS:

c start time for averaging
#define tSTATSTART uparam(1)

c output frequency for statistics
#define tSTATFREQ  uparam(2)

c drive flow with pressure gradient
#define DPDX uparam(3)

c mesh dimensions
#define PI (4.*atan(1.))
#define DELTA 1.
#define XLEN (2.*PI)
#define YLEN (2*DELTA)
#define ZLEN PI
#define NUMBER_ELEMENTS_X 16
#define NUMBER_ELEMENTS_Y 12
#define NUMBER_ELEMENTS_Z 8

c-----------------------------------------------------------------------
      subroutine uservp (ix,iy,iz,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'

      common /cdsmag/ ediff(lx1,ly1,lz1,lelv)

      ie     = gllel(ieg)
      udiff  = ediff(ix,iy,iz,ie)
      utrans = 1.

      return
      end
c-----------------------------------------------------------------------
      subroutine userf  (ix,iy,iz,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'
      common /cforce/ ffx_new,ffy_new,ffz_new

      ffx = ffx_new ! This value determined from fixed U_b=1 case.
      ffy = 0.0
      ffz = 0.0

      return
      end
c-----------------------------------------------------------------------
      subroutine userq  (ix,iy,iz,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'

      qvol   = 0.0
      source = 0.0

      return
      end
c-----------------------------------------------------------------------
      subroutine userchk
      include 'SIZE'
      include 'TOTAL'
      include 'ZPER'  ! for nelx,nely,nelz

      real x0(3)
      save x0

      integer icalld
      save    icalld
      data    icalld /0/

      real atime,timel
      save atime,timel

      integer ntdump
      save    ntdump

      common /cdsmag/ ediff(lx1,ly1,lz1,lelv)
      common /cforce/ ffx_new,ffy_new,ffz_new

      common /plane/  uavg_pl(ly1*lely)
     $             ,  urms_pl(ly1*lely)
     $             ,  vrms_pl(ly1*lely)
     $             ,  wrms_pl(ly1*lely)
     $             ,  uvms_pl(ly1*lely)
     $             ,  yy(ly1*lely)
     $             ,  w1(ly1*lely),w2(ly1*lely)
     $             ,  ffx_avg, dragx_avg

      common /avg/    uavg(lx1,ly1,lz1,lelv)
     &             ,  urms(lx1,ly1,lz1,lelv)
     &             ,  vrms(lx1,ly1,lz1,lelv)
     &             ,  wrms(lx1,ly1,lz1,lelv)
     &             ,  uvms(lx1,ly1,lz1,lelv)

      common /ctorq/ dragx(0:maxobj),dragpx(0:maxobj),dragvx(0:maxobj)
     $             , dragy(0:maxobj),dragpy(0:maxobj),dragvy(0:maxobj)
     $             , dragz(0:maxobj),dragpz(0:maxobj),dragvz(0:maxobj)
c
     $             , torqx(0:maxobj),torqpx(0:maxobj),torqvx(0:maxobj)
     $             , torqy(0:maxobj),torqpy(0:maxobj),torqvy(0:maxobj)
     $             , torqz(0:maxobj),torqpz(0:maxobj),torqvz(0:maxobj)
c
     $             , dpdx_mean,dpdy_mean,dpdz_mean
     $             , dgtq(3,4)

      integer e
      logical ifverbose
      common /gaaa/    wo1(lx1,ly1,lz1,lelv)
     &              ,  wo2(lx1,ly1,lz1,lelv)
     &              ,  wo3(lx1,ly1,lz1,lelv)

      real tplus

      n=nx1*ny1*nz1*nelv

      ! do some checks
      if (istep.eq.0) then
         if(mod(nely,2).ne.0) then
           if(nid.eq.0) write(6,*) 'ABORT: nely has to be even!'
           call exitt
         endif
         if(nelx.gt.lelx .or. nely.gt.lely .or. nelz.gt.lelz) then
           if(nid.eq.0) write(6,*) 'ABORT: nel_xyz > lel_xyz!'
           call exitt
         endif

         call set_obj                   ! objects for surface integrals
         call rzero(x0,3)               ! torque w.r.t. x0
      endif

      ! driving force for Ubar = 1
      call set_forcing(ffx_new,vx,1)

      ! Compute eddy viscosity using dynamic smagorinsky model
      if(ifuservp) then
        if(nid.eq.0) write(6,*) 'Calculating eddy visosity'
        do e=1,nelv   
           call eddy_visc(ediff,e)
        enddo
        call copy(t,ediff,n)
      endif


      ubar = glsc2(vx,bm1,n)/volvm1
      e2   = glsc3(vy,bm1,vy,n)+glsc3(vz,bm1,vz,n)
      e2   = e2/volvm1
      if(nid.eq.0) write(6,2) time,ubar,e2
   2               format(1p3e13.4,' monitor')

c
c     Below is just for postprocessing ...
c
      if (time.lt.tSTATSTART) goto 999 ! don't start averaging

      nelx  = NUMBER_ELEMENTS_X
      nely  = NUMBER_ELEMENTS_Y
      nelz  = NUMBER_ELEMENTS_Z

      rho    = 1.
      dnu    = param(2)
      A_w    = XLEN * ZLEN

      if(ifoutfld) then
        if(ldimt.ge.2) call lambda2(t(1,1,1,1,2))
        if(ldimt.ge.5) call comp_vort3(t(1,1,1,1,3),wo1,wo2,vx,vy,vz)
      endif

      call torque_calc(1.0,x0,.false.,.false.) ! wall shear

      if(icalld.eq.0) then
        call rzero(uavg,n)
        call rzero(urms,n)
        call rzero(vrms,n)
        call rzero(wrms,n)
        call rzero(uvms,n)
        dragx_avg = 0
        atime = 0
        timel = time
        call planar_average_s(yy,ym1,w1,w2)
        icalld = 1
        ntdump = int(time/tSTATFREQ)
        if(nid.eq.0) write(6,*) 'Start collecting statistics ...'
      endif

      dtime = time - timel
      atime = atime + dtime

      if (atime.ne.0. .and. dtime.ne.0.) then
        beta      = dtime/atime
        alpha     = 1.-beta
        ifverbose = .false.

        call avg1(uavg,vx   ,alpha,beta,n,'uavg',ifverbose)
        call avg2(urms,vx   ,alpha,beta,n,'urms',ifverbose)
        call avg2(vrms,vy   ,alpha,beta,n,'vrms',ifverbose)
        call avg2(wrms,vz   ,alpha,beta,n,'wrms',ifverbose)
        call avg3(uvms,vx,vy,alpha,beta,n,'uvmm',ifverbose)

        dragx_avg = alpha*dragx_avg + beta*0.5*(dragx(1)+dragx(2))

        ! averaging over statistical homogeneous directions (r-t)
        call planar_average_s(uavg_pl,uavg,w1,w2)
        call planar_average_s(urms_pl,urms,w1,w2)
        call planar_average_s(vrms_pl,vrms,w1,w2)
        call planar_average_s(wrms_pl,wrms,w1,w2)
        call planar_average_s(uvms_pl,uvms,w1,w2)

        ! average over half the channel height
        m = ny1*nely
        do i=1,ny1*nely/2
           uavg_pl(i) = 0.5 * (uavg_pl(i) + uavg_pl(m-i+1))
           urms_pl(i) = 0.5 * (urms_pl(i) + urms_pl(m-i+1))
           vrms_pl(i) = 0.5 * (vrms_pl(i) + vrms_pl(m-i+1))
           wrms_pl(i) = 0.5 * (wrms_pl(i) + wrms_pl(m-i+1))
        enddo
      endif

      ! write statistics to file
      if (nid.eq.0 .and. istep.gt.0 .and. 
     &   time.gt.(ntdump+1)*tSTATFREQ) then

         tw     = dragx_avg/A_w
         u_tau  = sqrt(tw/rho)
         Re_tau = u_tau*DELTA/dnu
         tplus  = time * Re_tau * u_tau

         ntdump = ntdump + 1
         write(6,*) 'Dumping statistics ...', tplus, Re_tau
 
         open(unit=56,file='vel_fluc_prof.dat')
         write(56,'(A,1pe14.7)') '#time = ', time
         write(56,'(A)')
     &   '#  y     y+     uu     vv     ww     uv'
         open(unit=57,file='mean_prof.dat')
         write(57,'(A,1pe14.7)') '#time = ', time
         write(57,'(A)')
     &   '#  y     y+    Umean'

         m = ny1*nely/2
         do i=1,m
            write(56,3) yy(i)+1
     &                ,(yy(i)+1)*Re_tau 
     &                , (urms_pl(i)-(uavg_pl(i))**2)/u_tau**2
     &                , vrms_pl(i)/u_tau**2
     &                , wrms_pl(i)/u_tau**2
     &                , uvms_pl(i)/u_tau**2
            write(57,3)  yy(i) + 1.
     &                , (yy(i)+1.)*Re_tau 
     &                , uavg_pl(i)/u_tau
    3       format(1p15e17.9)
        enddo
        close(56)
        close(57)
      endif

      timel = time
 999  continue

      return
      end
c-----------------------------------------------------------------------
      subroutine userbc (ix,iy,iz,iside,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'

      ux=0.0
      uy=0.0
      uz=0.0

      temp=0.0

      return
      end
c-----------------------------------------------------------------------
      subroutine useric (ix,iy,iz,ieg)
      include 'SIZE'
      include 'TOTAL'
      include 'NEKUSE'

      integer idum
      save    idum 
      data    idum / 0 /

      real C, k, kx, ky

      Re_tau = 550 
      C      = 5.17
      k      = 0.41

      yp = (1-y)*Re_tau
      if (y.lt.0) yp = (1+y)*Re_tau
      
c     Reichardt function
      ux  = 1/k*log(1+k*yp) + (C - (1/k)*log(k)) *
     $      (1 - exp(-yp/11) - yp/11*exp(-yp/3))
      ux  = ux * Re_tau*param(2)

c     perturb
      eps = 1e-2
      kx  = 23
      kz  = 13

      alpha = kx * 2*PI/XLEN
      beta  = kz * 2*PI/ZLEN 

      ux  = ux  + eps*beta  * sin(alpha*x)*cos(beta*z) 
      uy  =       eps       * sin(alpha*x)*sin(beta*z)
      uz  =      -eps*alpha * cos(alpha*x)*sin(beta*z)

      temp=0

      return
      end
c-----------------------------------------------------------------------
      subroutine usrdat   ! This routine to modify element vertices
      include 'SIZE'      ! _before_ mesh is generated, which 
      include 'TOTAL'     ! guarantees GLL mapping of mesh.

      common /cdsmag/ ediff(lx1,ly1,lz1,lelv)

      n=8*nelv
      xmin = glmin(xc,n)
      xmax = glmax(xc,n)
      ymin = glmin(yc,n)
      ymax = glmax(yc,n)
      zmin = glmin(zc,n)
      zmax = glmax(zc,n)

      xscale = XLEN/(xmax-xmin)
      yscale = YLEN/(ymax-ymin)
      zscale = ZLEN/(zmax-zmin)

      do i=1,n
         xc(i,1) = xscale*xc(i,1)
         yc(i,1) = yscale*yc(i,1)
         zc(i,1) = zscale*zc(i,1)
      enddo

      n = nx1*ny1*nz1*nelt 
      call cfill(ediff,param(2),n)  ! initialize viscosity

      return
      end
c-----------------------------------------------------------------------
      subroutine usrdat2   ! This routine to modify mesh coordinates
      include 'SIZE'
      include 'TOTAL'

      return
      end
c-----------------------------------------------------------------------
      subroutine usrdat3
      include 'SIZE'
      include 'TOTAL'

      return
      end
c-----------------------------------------------------------------------
      subroutine set_obj  ! define objects for surface integrals
c
      include 'SIZE'
      include 'TOTAL'
c
      integer e,f
c
c     Define new objects
c
      nobj = 2			! for Periodic
      iobj = 0
      do ii=nhis+1,nhis+nobj
         iobj = iobj+1
         hcode(10,ii) = 'I'
         hcode( 1,ii) = 'F' ! 'F'
         hcode( 2,ii) = 'F' ! 'F'
         hcode( 3,ii) = 'F' ! 'F'
         lochis(1,ii) = iobj
      enddo
      nhis = nhis + nobj
c
      if (maxobj.lt.nobj) write(6,*) 'increase maxobj in SIZEu. rm *.o'
      if (maxobj.lt.nobj) call exitt
c
      nxyz = nx1*ny1*nz1
      do e=1,nelv
      do f=1,2*ndim
         if (cbc(f,e,1).eq.'W  ') then
            iobj = 0
            if (f.eq.1) iobj=1  ! lower wall
            if (f.eq.3) iobj=2  ! upper wall
            if (iobj.gt.0) then
               nmember(iobj) = nmember(iobj) + 1
               mem = nmember(iobj)
               ieg = lglel(e)
               object(iobj,mem,1) = ieg
               object(iobj,mem,2) = f
c              write(6,1) iobj,mem,f,ieg,e,nid,' OBJ'
    1          format(6i9,a4)
            endif
c
         endif
      enddo
      enddo
c     write(6,*) 'number',(nmember(k),k=1,4)
c
      return
      end
c-----------------------------------------------------------------------
      subroutine comp_lij(lij,u,v,w,fu,fv,fw,fh,fht,e)
c
c     Compute Lij for dynamic Smagorinsky model:
c                    _   _      _______
c          L_ij  :=  u_i u_j  - u_i u_j
c
      include 'SIZE'
c
      integer e
c
      real lij(lx1*ly1*lz1,3*ldim-3)
      real u  (lx1*ly1*lz1,lelv)
      real v  (lx1*ly1*lz1,lelv)
      real w  (lx1*ly1*lz1,lelv)
      real fu (1) , fv (1) , fw (1)
     $   , fh (1) , fht(1)

      call tens3d1(fu,u(1,e),fh,fht,nx1,nx1)  ! fh x fh x fh x u
      call tens3d1(fv,v(1,e),fh,fht,nx1,nx1)
      call tens3d1(fw,w(1,e),fh,fht,nx1,nx1)

      n = nx1*ny1*nz1
      do i=1,n
         lij(i,1) = fu(i)*fu(i)
         lij(i,2) = fv(i)*fv(i)
         lij(i,3) = fw(i)*fw(i)
         lij(i,4) = fu(i)*fv(i)
         lij(i,5) = fv(i)*fw(i)
         lij(i,6) = fw(i)*fu(i)
      enddo
      
      call col3   (fu,u(1,e),u(1,e),n)    !  _______
      call tens3d1(fv,fu,fh,fht,nx1,nx1)  !  u_1 u_1
      call sub2   (lij(1,1),fv,n)
      
      call col3   (fu,v(1,e),v(1,e),n)    !  _______
      call tens3d1(fv,fu,fh,fht,nx1,nx1)  !  u_2 u_2
      call sub2   (lij(1,2),fv,n)
      
      call col3   (fu,w(1,e),w(1,e),n)    !  _______
      call tens3d1(fv,fu,fh,fht,nx1,nx1)  !  u_3 u_3
      call sub2   (lij(1,3),fv,n)
      
      call col3   (fu,u(1,e),v(1,e),n)    !  _______
      call tens3d1(fv,fu,fh,fht,nx1,nx1)  !  u_1 u_2
      call sub2   (lij(1,4),fv,n)
      
      call col3   (fu,v(1,e),w(1,e),n)    !  _______
      call tens3d1(fv,fu,fh,fht,nx1,nx1)   !  u_2 u_3
      call sub2   (lij(1,5),fv,n)
      
      call col3   (fu,w(1,e),u(1,e),n)    !  _______
      call tens3d1(fv,fu,fh,fht,nx1,nx1)  !  u_3 u_1
      call sub2   (lij(1,6),fv,n)

      return
      end
c-----------------------------------------------------------------------
      subroutine comp_mij(mij,sij,dg2,fs,fi,fh,fht,nt,e)
c
c     Compute Mij for dynamic Smagorinsky model:
c
c                     2 _  ____     _______
c          M_ij  :=  a  S  S_ij  -  S  S_ij
c
      include 'SIZE'
c
      integer e
c
      real mij(lx1*ly1*lz1,3*ldim-3)
      real dg2(lx1*ly1*lz1,lelv)
      real fs (1) , fi (1) , fh (1) , fht(1)

      real magS(lx1*ly1*lz1)
      real sij (lx1*ly1*lz1*ldim*ldim)
      
      integer imap(6)
      data imap / 0,4,8,1,5,2 /

      n = nx1*ny1*nz1

      call mag_tensor_e(magS,sij)
      call cmult(magS,2.0,n)

c     Filter S
      call tens3d1(fs,magS,fh,fht,nx1,nx1)  ! fh x fh x fh x |S|

c     a2 is the test- to grid-filter ratio, squared

      a2 = nx1-1       ! nx1-1 is number of spaces in grid
      a2 = a2 /(nt-1)  ! nt-1 is number of spaces in filtered grid

      do k=1,6
         jj = n*imap(k) + 1
         call col3   (fi,magS,sij(jj),n)
         call tens3d1(mij(1,k),fi,fh,fht,nx1,nx1)  ! fh x fh x fh x (|S| S_ij)
         call tens3d1(fi,sij(jj),fh,fht,nx1,nx1)  ! fh x fh x fh x S_ij
         do i=1,n
            mij(i,k) = (a2**2 * fs(i)*fi(i) - mij(i,k))*dg2(i,e)
         enddo
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine eddy_visc(ediff,e)
c
c     Compute eddy viscosity using dynamic smagorinsky model
c
      include 'SIZE'
      include 'TOTAL'
      include 'ZPER'

      real ediff(nx1*ny1*nz1,nelv)
      integer e

      common /dynsmg/ sij (lx1*ly1*lz1,ldim,ldim)
     $              , mij (lx1*ly1*lz1,3*ldim-3)
     $              , lij (lx1*ly1*lz1,3*ldim-3)
     $              , dg2 (lx1*ly1*lz1,lelv)
     $              , num (lx1*ly1*lz1,lelv)
     $              , den (lx1*ly1*lz1,lelv)
     $              , snrm(lx1*ly1*lz1,lelv)
     $              , numy(ly1*lely),deny(ly1*lely),yy(ly1*lely)
      real sij,mij,lij,dg2,num,den,snrm,numy,deny,yy

      parameter(lxyz=lx1*ly1*lz1)
      common /xzmp0/ ur (lxyz) , us (lxyz) , ut (lxyz)
      real           vr (lxyz) , vs (lxyz) , vt (lxyz)
     $     ,         wr (lxyz) , ws (lxyz) , wt (lxyz)
      common /xzmp1/ w1(lx1*lelv),w2(lx1*lelv)

      !! NOTE CAREFUL USE OF EQUIVALENCE HERE !!
      equivalence (vr,lij(1,1)),(vs,lij(1,2)),(vt,lij(1,3))
     $          , (wr,lij(1,4)),(ws,lij(1,5)),(wt,lij(1,6))

      common /sgsflt/ fh(lx1*lx1),fht(lx1*lx1),diag(lx1)

      integer nt
      save    nt
      data    nt / -9 /

      ntot = nx1*ny1*nz1

      if (nt.lt.0) call
     $   set_ds_filt(fh,fht,nt,diag,nx1)! dyn. Smagorinsky filter

      call comp_gije(sij,vx(1,1,1,e),vy(1,1,1,e),vz(1,1,1,e),e)
      call comp_sije(sij)

      call mag_tensor_e(snrm(1,e),sij)
      call cmult(snrm(1,e),2.0,ntot)

      call set_grid_spacing(dg2)
      call comp_mij   (mij,sij,dg2,ur,us,fh,fht,nt,e)

      call comp_lij   (lij,vx,vy,vz,ur,us,ut,fh,fht,e)

c     Compute numerator (ur) & denominator (us) for Lilly contraction

      n = nx1*ny1*nz1
      do i=1,n
         ur(i) = mij(i,1)*lij(i,1)+mij(i,2)*lij(i,2)+mij(i,3)*lij(i,3)
     $      + 2*(mij(i,4)*lij(i,4)+mij(i,5)*lij(i,5)+mij(i,6)*lij(i,6))
         us(i) = mij(i,1)*mij(i,1)+mij(i,2)*mij(i,2)+mij(i,3)*mij(i,3)
     $      + 2*(mij(i,4)*mij(i,4)+mij(i,5)*mij(i,5)+mij(i,6)*mij(i,6))
      enddo
      
c     smoothing numerator and denominator in time
      call copy (vr,ur,nx1*nx1*nx1)
      call copy (vs,us,nx1*nx1*nx1)

      beta1 = 0.0                   ! Temporal averaging coefficients
      if (istep.gt.1) beta1 = 0.9   ! Retain 90 percent of past
      beta2 = 1. - beta1

      do i=1,n
         num (i,e) = beta1*num(i,e) + beta2*vr(i)
         den (i,e) = beta1*den(i,e) + beta2*vs(i)
      enddo


      if (e.eq.nelv) then  ! planar avg and define nu_tau

         call dsavg(num)   ! average across element boundaries
         call dsavg(den)

         call planar_average_s      (numy,num,w1,w2)
c        call wall_normal_average_s (numy,ny1,nely,w1,w2)
         call planar_fill_s         (num,numy)

         call planar_average_s      (deny,den,w1,w2)
c        call wall_normal_average_s (deny,ny1,nely,w1,w2)
         call planar_fill_s         (den,deny)

         call planar_average_s(yy,ym1,w1,w2)

c - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
c DIAGNOSTICS ONLY
c         if (nid.eq.0.and.istep.eq.0) open(unit=55,file='z.z')
c         if (nid.eq.0.and.mod(istep,10).eq.0) write(55,1)
c    1    format(/)
c
c         ny = ny1*nely   
c         do i=1,ny
c            cdyn = 0
c            if (deny(i).gt.0) cdyn = 0.5*numy(i)/deny(i)
c            cdyn0 = max(cdyn,0.)
c            if (nid.eq.0.and.mod(istep,10).eq.0) write(55,6) 
c     $         istep,i,time,yy(i),cdyn0,cdyn,numy(i),deny(i)
c    6       format(i6,i4,1p6e12.4)
c         enddo               
c DIAGNOSTICS ONLY
c - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

         ntot = nx1*ny1*nz1*nelv
         do i=1,ntot
            cdyn = 0
            if (den(i,1).gt.0) cdyn = 0.5*num(i,1)/den(i,1)
            cdyn = max(cdyn,0.)   ! AS ALTERNATIVE, could clip ediff
            ediff(i,1) = param(2)+cdyn*dg2(i,1)*snrm(i,1)
         enddo
      endif
      
c     if (e.eq.nelv) call outpost(num,den,snrm,den,ediff,'dif')
c     if (e.eq.nelv) call exitt

      return
      end
c-----------------------------------------------------------------------
      subroutine set_ds_filt(fh,fht,nt,diag,nx) ! setup test filter

      INCLUDE 'SIZE'

      real fh(nx*nx),fht(nx*nx),diag(nx)

c Construct transfer function
      call rone(diag,nx)

c      diag(nx-0) = 0.01   
c      diag(nx-1) = 0.10  
c      diag(nx-2) = 0.50
c      diag(nx-3) = 0.90
c      diag(nx-4) = 0.99
c      nt = nx - 2

      diag(nx-0) = 0.05   
      diag(nx-1) = 0.50
      diag(nx-2) = 0.95
      nt = nx - 1

      call build_1d_filt(fh,fht,diag,nx,nid)

      return
      end
c-----------------------------------------------------------------------
      subroutine planar_average_r(ua,u,w1,w2)
c
c     Compute s-t planar average of quantity u()
c
      include 'SIZE'
      include 'GEOM'
      include 'PARALLEL'
      include 'WZ'
      include 'ZPER'
c
      real ua(nx1,lelx),u(nx1,ny1,nx1,nelv),w1(nx1,lelx),w2(nx1,lelx)
      integer e,eg,ex,ey,ez
c
      nx = nx1*nelx
      call rzero(ua,nx)
      call rzero(w1,nx)
c
      do e=1,nelt
c
         eg = lglel(e)
         call get_exyz(ex,ey,ez,eg,nelx,nely,nelz)
c
         do i=1,nx1
         do k=1,nz1
         do j=1,ny1
            zz = (1.-zgm1(i,1))/2.  ! = 1 for i=1, = 0 for k=nx1
            aa = zz*area(j,k,4,e) + (1-zz)*area(j,k,2,e)  ! wgtd jacobian
            w1(i,ex) = w1(i,ex) + aa
            ua(i,ex) = ua(i,ex) + aa*u(i,j,k,e)
         enddo
         enddo
         enddo
      enddo
c
      call gop(ua,w2,'+  ',nx)
      call gop(w1,w2,'+  ',nx)
c
      do i=1,nx
         ua(i,1) = ua(i,1) / w1(i,1)   ! Normalize
      enddo
c
      return
      end
c-----------------------------------------------------------------------
      subroutine planar_average_s(ua,u,w1,w2)
c
c     Compute r-t planar average of quantity u()
c
      include 'SIZE'
      include 'GEOM'
      include 'PARALLEL'
      include 'WZ'
      include 'ZPER'
c
      real ua(ny1,nely),u(nx1,ny1,nx1,nelv),w1(ny1,nely),w2(ny1,nely)
      integer e,eg,ex,ey,ez
c
      ny = ny1*nely
      call rzero(ua,ny)
      call rzero(w1,ny)
c
      do e=1,nelt
         eg = lglel(e)
         call get_exyz(ex,ey,ez,eg,nelx,nely,nelz)
c
         do k=1,nz1
         do j=1,ny1
         do i=1,nx1
            zz = (1.-zgm1(j,2))/2.  ! = 1 for i=1, = 0 for k=nx1
            aa = zz*area(i,k,1,e) + (1-zz)*area(i,k,3,e)  ! wgtd jacobian
            w1(j,ey) = w1(j,ey) + aa
            ua(j,ey) = ua(j,ey) + aa*u(i,j,k,e)
         enddo
         enddo
         enddo
      enddo
c
      call gop(ua,w2,'+  ',ny)
      call gop(w1,w2,'+  ',ny)
c
      do i=1,ny
         ua(i,1) = ua(i,1) / w1(i,1)   ! Normalize
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine planar_fill_s(u,ua)
c
c     Fill array u with planar values from ua().
c     For tensor-product array of spectral elements
c
      include 'SIZE'
      include 'GEOM'
      include 'PARALLEL'
      include 'WZ'
      include 'ZPER'


      real u(nx1,ny1,nz1,nelv),ua(ly1,lely)

      integer e,eg,ex,ey,ez

      melxyz = nelx*nely*nelz
      if (melxyz.ne.nelgt) then
         write(6,*) nid,' Error in planar_fill_s'
     $                 ,nelgt,melxyz,nelx,nely,nelz
         call exitt
      endif

      do e=1,nelt
         eg = lglel(e)
         call get_exyz(ex,ey,ez,eg,nelx,nely,nelz)

         do j=1,ny1
         do k=1,nz1
         do i=1,nx1
            u(i,j,k,e) = ua(j,ey)
         enddo
         enddo
         enddo

      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine set_grid_spacing(dg2)
c
c     Compute D^2, the grid spacing used in the DS sgs model.
c
      include 'SIZE'
      include 'TOTAL'


      real dg2(nx1,ny1,nz1,nelv)

      integer e,eg,ex,ey,ez

      gamma = 1.
      gamma = gamma/ndim

      n = nx1*ny1*nz1*nelv
      call rone(dg2,n)
      return               ! Comment this line for a non-trivial Delta defn

      do e=1,nelv

         do k=1,nz1
           km = max(1  ,k-1)
           kp = min(nz1,k+1)

           do j=1,ny1
             jm = max(1  ,j-1)
             jp = min(ny1,j+1)

             do i=1,nx1
               im = max(1  ,i-1)
               ip = min(nx1,i+1)

               di = (xm1(ip,j,k,e)-xm1(im,j,k,e))**2
     $            + (ym1(ip,j,k,e)-ym1(im,j,k,e))**2
     $            + (zm1(ip,j,k,e)-zm1(im,j,k,e))**2

               dj = (xm1(i,jp,k,e)-xm1(i,jm,k,e))**2
     $            + (ym1(i,jp,k,e)-ym1(i,jm,k,e))**2
     $            + (zm1(i,jp,k,e)-zm1(i,jm,k,e))**2

               dk = (xm1(i,j,kp,e)-xm1(i,j,km,e))**2
     $            + (ym1(i,j,kp,e)-ym1(i,j,km,e))**2
     $            + (zm1(i,j,kp,e)-zm1(i,j,km,e))**2
               
               di = di/(ip-im)
               dj = dj/(jp-jm)
               dk = dk/(kp-km)
               dg2(i,j,k,e) = (di*dj*dk)**gamma

             enddo
           enddo
         enddo
      enddo

      call dsavg(dg2)  ! average neighboring elements

      return
      end
c-----------------------------------------------------------------------
      subroutine wall_normal_average_s(u,ny,nel,v,w)
      real u(ny,nel),w(1),v(1)
      integer e

      k=0
      do e=1,nel    ! get rid of duplicated (ny,e),(1,e+1) points
      do i=1,ny-1
         k=k+1
         w(k) = u(i,e)
      enddo
      enddo
      k=k+1
      w(k) = u(ny,nel)
      n=k

      npass = 2     ! Smooth
      alpha = 0.2

      do ipass=1,npass
         do k=2,n-1
            v(k) = (1.-alpha)*w(k) + 0.5*alpha*(w(k-1)+w(k+1))
         enddo

         do k=1,n
            w(k) = v(k)
         enddo
      enddo

      k=0
      do e=1,nel    ! restore duplicated (ny,e),(1,e+1) points
         do i=1,ny-1
            k=k+1
            u(i,e) = w(k)
         enddo
      enddo
      k=k+1
      u(ny,nel)=w(k)

      do e=1,nel-1    ! restore duplicated (ny,e),(1,e+1) points
         u(ny,e) = u(1,e+1)
      enddo
      return
      end
c-----------------------------------------------------------------------
      subroutine set_forcing(f_new,u,idir)  ! driving force for Ubar = 1

      include 'SIZE'
      include 'TOTAL'

      common /uforce/ utldo(ldim)

      n=nx1*ny1*nz1*nelv

      if (istep.eq.0) then
         f_new = 0.
         if (DPDX.eq.1) then
            param(54) = -1 ! flow direction (x:1, y:2, z:3)
            param(55) = 1  ! flowrate (p54>) or Ubar (p54<0)
         endif
      endif

      if (DPDX.eq.1) return

      u_targ  = 1.
      ubar    = glsc2(u,bm1,n)/volvm1
      utilde  = ubar/u_targ

      if (istep.gt.0) f_new = 0.5 * (f_new + f_new/utilde)

      if (istep.gt.5) then
         alpha = abs(utilde-utldo(idir))/dt
         alpha = min(alpha,0.05)
         if     (utilde.gt.1.and.utilde.gt.utldo(idir)) then
            f_new = (1-alpha)*f_new
         elseif (utilde.lt.1.and.utilde.lt.utldo(idir)) then
            f_new = (1+alpha)*f_new
         endif
      endif
      utldo(idir)   = utilde

      f_min = 0.00001                 ! ad hoc limits
      f_new = max(f_new,f_min)
      
      f_max = 0.10000                 ! ad hoc limits
      f_new = min(f_new,f_max)
      
      return
      end
c
c automatically added by makenek
      subroutine usrsetvert(glo_num,nel,nx,ny,nz) ! to modify glo_num
      integer*8 glo_num(1)
      return
      end

c automatically added by makenek
      subroutine userqtl

      call userqtl_scig

      return
      end
